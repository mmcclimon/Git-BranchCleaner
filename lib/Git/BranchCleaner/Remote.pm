use v5.30;
package Git::BranchCleaner::Remote;
# ABSTRACT: clean up your remote git branches

use Moo;
extends 'Git::BranchCleaner';
use experimental 'signatures';

# lol, terrible
my sub _log    { goto &Git::BranchCleaner::_log    }
my sub run_git { goto &Git::BranchCleaner::run_git }

sub process_refs ($self) {
  for my $branch (sort keys $self->remote_shas->%*) {
    next if $self->_is_eternal->{$branch};

    my $remote_sha = $self->remote_shas->{$branch};
    my $full_branch = join q{/}, $self->personal_remote, $branch;

    my $main_sha = $self->check_merged($branch, $remote_sha);
    if ($main_sha) {
      my $main = $self->main_name;
      _log(merged => "$full_branch appears in $main as $main_sha; will delete");
      push $self->to_delete->@*, $branch;
      next;
    }

    _log(note => "$full_branch is unmerged; skipping")
  }
}

sub make_changes ($self) {
  if ($self->to_delete->@*) {
    run_git('push', '-d', $self->personal_remote, $self->to_delete->@*);
    _log(ok => "deleted $_") for $self->to_delete->@*;
  }
}

1;
