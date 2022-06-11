use v5.30;
package Git::BranchCleaner;
# ABSTRACT: clean up your local git branches

use Moo;
use experimental 'signatures';

use Carp qw(confess);
use Capture::Tiny qw(capture_merged);
use IPC::System::Simple qw(systemx);
use POSIX qw(SIGINT);
use Process::Status;
use Term::ANSIColor qw(colored);

has upstream_remote => (
  is => 'ro',
  default => 'gitbox',
);

has personal_remote => (
  is => 'ro',
  default => 'michael',
);

has eternal_branches => (
  is => 'ro',
  default => sub { [qw( main master )] },
);

has _is_eternal => (
  is => 'ro',
  lazy => 1,
  default => sub ($self) { +{ map {; $_ => 1 } $self->eternal_branches->@* } }
);

has [qw( local_shas remote_shas other_upstreams )] => (
  is => 'rwp',
  init_arg => undef,
);

has [qw( to_push to_delete )] => (
  is => 'ro',
  default => sub { [] },
);

has to_update => (
  is => 'ro',
  default => sub { {} },
);

has [qw( really skip_initial_fetch )] => (
  is => 'rwp',
  default => 0,
);

has interactive => (
  is => 'ro',
  default => 1,
);

has main_name => (
  is => 'ro',
  default => 'main',
);

sub run ($self) {
  $self->assert_local_ok;
  $self->do_initial_fetch;
  $self->read_refs;
  $self->process_refs;
  $self->get_confirmation if $self->interactive && ! $self->really;
  $self->make_changes if $self->really;
}

# internal subs
our sub _log ($level, $msg, $arg = {}) {
  state %prefix_for = (
    note   => colored('NOTE    ', 'clear'),
    merged => colored('MERGED  ', 'green'),
    update => colored('UPDATE  ', 'bright_cyan'),
    warn   => colored('WARN    ', 'bright_yellow'),
    ok     => colored('OK      ', 'green'),
  );

  print "\n" if $arg->{prefix_newline};

  my $prefix = $prefix_for{$level} // confess("bad level: $level");
  say "$prefix $msg";
}

our sub run_git (@args) {
  my @cmd = ('git', @args);
  my $out = capture_merged { system @cmd };

  my $ps = Process::Status->new;

  # catch ^C and bail immediately
  if ($ps->signal == SIGINT) {
    _log(warn => "caught SIGINT, bailing out", { prefix_newline => 1 });
    exit 1;
  }

  unless ($ps->is_success) {
    _log(warn => "Error executing @cmd: " . $ps->as_string);
  }

  my @lines = split /\n/, $out;
  return wantarray ? @lines : $lines[0];
}

my sub fetch ($remote) {
  _log(note => "fetching $remote");
  run_git('fetch', $remote);
}

# main subs
sub assert_local_ok ($self) {
  my @status = run_git(qw( status --branch --porcelain=v2) );
  my ($branch_line) = grep {; /branch\.head/ } @status;
  my ($branch) = $branch_line =~ /branch\.head (.*)/;

  die "could not read status?\n" unless $branch;
  die "cannot proceed from branch $branch\n" unless $branch eq $self->main_name;
}

sub do_initial_fetch ($self) {
  return if $self->skip_initial_fetch;
  fetch($self->upstream_remote);
  fetch($self->personal_remote);
}

sub read_refs ($self) {
  my $remote = $self->personal_remote;

  my @refs = run_git(
    'for-each-ref',
    '--format=%(objectname) %(objecttype) %(refname) %(upstream)',
    'refs/heads',
    "refs/remotes/$remote",
  );

  my %local;
  my %remote;
  my %other;

  for my $line (@refs) {
    my ($sha, $type, $ref, $upstream) = split /\s+/, $line;
    next unless $type eq 'commit';

    if ($ref =~ m{refs/heads/(.*)}) {
      # local branch
      my $branch = $1;

      next if $self->_is_eternal->{$branch};

      if ($upstream && $upstream !~ m{refs/remotes/\Q$remote\E}) {
        $upstream =~ s|^refs/remotes/||;
        $other{$branch} = $upstream;
      }

      $local{$branch} = $sha;
    }

    if ($ref =~ m{refs/remotes/\Q$remote\E/(.*)}) {
      # personal remote
      my $branch = $1;
      $remote{$branch} = $sha;
    }
  }

  $self->_set_local_shas(\%local);
  $self->_set_remote_shas(\%remote);
  $self->_set_other_upstreams(\%other);
}

sub process_refs ($self) {
  # For every local branch...
  for my $branch (sort keys $self->local_shas->%*) {
    my $local_sha  = $self->local_shas->{$branch};
    my $remote_sha = $self->remote_shas->{$branch};

    my $main_sha = $self->check_merged($branch, $local_sha);
    if ($main_sha) {
      my $main = $self->main_name;
      _log(merged => "$branch appears in $main as $main_sha");
      push $self->to_delete->@*, $branch;
      next;
    }

               # is it someone else's ref?
    my $method = $self->other_upstreams->{$branch} ? '_process_external'
               # do we have it on our remote?
               : ! $remote_sha                     ? '_process_missing'
               # do we agree with our remote?
               : $remote_sha eq $local_sha         ? '_process_matched'
               # do we disagree with our remote?
               : $remote_sha ne $local_sha         ? '_process_mismatched'
               : confess 'unreachable';

    $self->$method($branch);
  }
}

sub _process_external ($self, $branch) {
  state %fetched;

  my $local_sha = $self->local_shas->{$branch};
  my $tracking_branch = $self->other_upstreams->{$branch};

  my ($who) = split m{/}, $tracking_branch;
  fetch($who) unless $fetched{$who}++;

  my $upstream_sha = run_git(qw(show --no-patch --format=%H), "refs/remotes/$tracking_branch");

  if ($upstream_sha eq $local_sha) {
    _log(ok => "$branch matches $tracking_branch");
    return;
  }

  _log(update => "$branch; $tracking_branch has changed; will update local");
  $self->to_update->{$branch} = $upstream_sha;
}

sub _process_missing ($self, $branch) {
  _log(warn => "$branch has no matching remote and is not merged");
}

sub _process_matched ($self, $branch) {
  _log(ok => "$branch already up to date");
}

sub _process_mismatched ($self, $branch) {
  my $local = $self->local_shas->{$branch};
  my $remote = $self->remote_shas->{$branch};

  my $local_time  = run_git(qw(show --no-patch --format=%ct), $local);
  my $remote_time = run_git(qw(show --no-patch --format=%ct), $remote);

  if ($local_time > $remote_time) {
    _log(update => "$branch is newer locally; will push");
    push $self->to_push->@*, $branch;
  } else {
    _log(update => "$branch is newer on remote; will update local");
    $self->to_update->{$branch} = $remote;
  }
}

sub check_merged ($self, $branch, $have_sha) {
  my $subject = run_git(qw(show --no-patch --format=%s), $have_sha);

  my $patch = qx(git diff-tree -p $have_sha | git patch-id);
  my ($patch_id) = split /\s+/, $patch;

  # this stinks
  my @sha = run_git(qw(log --no-merges --format=%h -n 10 --grep), $subject);

  # find the matching patch id, if we have one
  for my $sha (@sha) {
    my $check = qx(git diff-tree -p $sha | git patch-id);
    my ($check_id) = split /\s+/, $check;

    if ($check_id eq $patch_id) {
      return substr $sha, 0, 8;
    }
  }

  if (@sha == 10) {
    my $main = $self->main_name;
    _log(warn => "$branch: subject matched > 10 commits in $main; assuming unmerged");
  }

  return;
}

sub has_changes ($self) {
  return $self->to_delete->@*
      || $self->to_push->@*
      || $self->to_update->%*;
}

sub get_confirmation ($self) {
  return unless $self->has_changes;

  print "Make changes? [y/n] ";
  chomp (my $answer = <STDIN>);

  if ((lc $answer // '') eq 'y') {
    $self->_set_really(1);
  }
}

sub make_changes ($self) {
  if ($self->to_delete->@*) {
    run_git('branch', '-D', $self->to_delete->@*);
    _log(ok => "deleted $_") for $self->to_delete->@*;
  }

  for my $branch ($self->to_push->@*) {
    run_git('push', '--force-with-lease', $self->personal_remote, "$branch:$branch");
    _log(ok => "pushed $branch");
  }

  for my $branch (sort keys $self->to_update->%*) {
    my $new = $self->to_update->{$branch};
    run_git('update-ref', "refs/heads/$branch", $new);
    _log(ok => "updated $branch");
  }
}

1;
