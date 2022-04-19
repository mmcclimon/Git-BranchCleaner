# This file is generated by Dist::Zilla::Plugin::CPANFile v6.020
# Do not edit this file directly. To change prereqs, edit the `dist.ini` file.

requires "Capture::Tiny" => "0";
requires "Carp" => "0";
requires "Defined::KV" => "0";
requires "Getopt::Long::Descriptive" => "0";
requires "IPC::System::Simple" => "0";
requires "Moo" => "0";
requires "Process::Status" => "0";
requires "Term::ANSIColor" => "0";
requires "experimental" => "0";
requires "perl" => "v5.30.0";
requires "warnings" => "0";

on 'test' => sub {
  requires "ExtUtils::MakeMaker" => "0";
  requires "File::Spec" => "0";
  requires "Test::More" => "0.96";
  requires "strict" => "0";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "2.120900";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "0";
};

on 'develop' => sub {
  requires "Encode" => "0";
  requires "Test::More" => "0";
  requires "Test::Pod" => "1.41";
  requires "strict" => "0";
};
