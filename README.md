# Git::BranchCleaner

It cleans your branches.

```perl
Git::BranchCleaner->new({
  upstream_remote => 'origin',              # default: gitbox
  personal_remote => 'yourname',            # default: michael
  eternal_branches => ['main', 'beta'],     # default: main, master
})->run;
```
