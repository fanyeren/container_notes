#!/usr/bin/env perl

# fork from https://gist.github.com/mpasternacki/6660958
# the original script is too old according latest docker.

use feature 'switch';
use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Path qw/make_path/;
use File::Temp qw/tempdir/;

use JSON;

our ( $from, $author, %metadata, @commands, $tmpdir, $tmpcount, $prefix );

$tmpdir = tempdir(CLEANUP => !$ENV{LEAVE_TMPDIR});
$tmpcount = 0;
$prefix = '';

print "*** Working directory: $tmpdir\n" if $ENV{LEAVE_TMPDIR};

open DOCKERFILE, '<Dockerfile' or die;
while ( <DOCKERFILE> ) {
  chomp;

  # handle long lines
  $_ = "$prefix$_";
  $prefix = '';
  if ( /\\$/ ) {
    s/\\$//;
    $prefix="$_\n";
    next;
  }

  s/^\s*//;
  /^#/ and next;
  /^$/ and next;

  my ($cmd, $args) = split(/\s+/, $_, 2);
  given ( uc $cmd ) {
    # building the image
    when ('FROM') { $from = $args }
    when ('RUN')  { push @commands, $args }
    when ('COPY')  {
      $tmpcount++;
      my $chown;
      if ( $args =~ m/^--chown=/ ) {
          ( $chown, $args ) = split ' ', $args, 2;
          ( my $_unused, $chown) = split '=', $chown, 2;
      }
      my ( $src, $dest ) = split ' ', $args, 2;

      my $local = "$tmpdir/$tmpcount";

      if ( -f $src ) {
        # TODO, $dest is directory but dont have trailing slash.
        $dest .= basename($src) if ( $dest =~ /\/$/ );
        system('cp', '-a', $src, $local) == 0 or die;
        push @commands, "mkdir -p '".dirname($dest)."'", "cp -a /.data/$tmpcount '$dest'";
        push @commands, "chown -R '$chown' '$dest'" if defined $chown;
      } elsif ( -d $src ) {
        # Handle trailing slash combinations properly:
        # - `$src=/dir,  $dest=/foo  -> /foo`
        # - `$src=/dir,  $dest=/foo/ -> /foo/dir`
        # - `$src=/dir/, $dest=/foo  -> /foo`
        # - `$src=/dir/, $dest=/foo/ -> /foo`
        $dest .= basename($src) if ( $src !~ /\/$/ && $dest =~ /\/$/ );

        system('cp', '-a', $src, $local) == 0 or die;
        push @commands, "mkdir -p '$dest'", "( cd /.data/$tmpcount ; cp -a . '$dest' )";
        push @commands, "chown -R '$chown' '$dest'" if defined $chown;
      }
    }
    when ('ADD')  {
      $tmpcount++;
      my ( $src, $dest ) = split ' ', $args, 2;

      if ( $src =~ /^https?:/ ) {
        my $basename = basename($src);
        my $target = "$tmpdir/dl/$tmpcount/$basename";
        make_path "$tmpdir/dl/$tmpcount";
        system('wget', '-O', $target, $src) == 0 or die;
        $src = $target;
      }

      my $local = "$tmpdir/$tmpcount";

      given ( $src ) {
        when ( /\.(tar(\.(gz|bz2|xz))?|tgz)$/ ) {
          mkdir $local;
          system('tar', '-C', $local, '-xf', $_) == 0 or die;
          push @commands, "mkdir -p '$dest'", "( cd /.data/$tmpcount ; cp -a . '$dest' )";
        }
        when ( -f $_ ) {
          $dest .= basename($_) if ( $dest =~ /\/$/ );
          system('cp', '-a', $_, $local) == 0 or die;
          push @commands, "mkdir -p '".dirname($dest)."'", "cp -a /.data/$tmpcount '$dest'";
        }
        when ( -d $_ ) {
          # Handle trailing slash combinations properly:
          # - `$src=/dir,  $dest=/foo  -> /foo`
          # - `$src=/dir,  $dest=/foo/ -> /foo/dir`
          # - `$src=/dir/, $dest=/foo  -> /foo`
          # - `$src=/dir/, $dest=/foo/ -> /foo`
          $dest .= basename($_) if ( $_ !~ /\/$/ && $dest =~ /\/$/ );

          system('cp', '-a', $_, $local) == 0 or die;
          push @commands, "mkdir -p '$dest'", "( cd /.data/$tmpcount ; cp -a . '$dest' )";
        }
        default { die }
      }
    }

    # image metadata
    when ('MAINTAINER') { $author = $args }
    when ('CMD')        { $metadata{Cmd} =        eval { decode_json($args) } || ['sh', '-c', $args] }
    when ('ENTRYPOINT') { $metadata{Entrypoint} = eval { decode_json($args) } || ['sh', '-c', $args] }
    when ('WORKDIR')    { $metadata{WORKDIR} = $args }
    when ('USER')       { $metadata{User}       = $args }
    when ('EXPOSE')     { push @{ $metadata{PortSpecs} ||= [] },   split(' ',$args); }
    when ('ENV')        {
      my ( $k, $v ) = split(/\s+/, $args, 2);
      push @commands, "export $k='$v'";
      push @{ $metadata{ENV} ||= [] }, "$k $v";
    }
    when ('VOLUME')     {
      # This seems to be a NOP in `docker build`.
      # push @{ $metadata{VolumesFrom} ||= [] }, $args
    }
  }
}
close DOCKERFILE;

open SETUP, ">$tmpdir/setup.sh" or die;
print SETUP join("\n", "#!/bin/sh", "set -e -x", @commands), "\ntouch /.data/FINI\n";
close SETUP;
chmod 0755, "$tmpdir/setup.sh";

our @run = ('sudo', 'docker', 'run', "--cidfile=$tmpdir/CID", '-v', "$tmpdir:/.data", $from, "/.data/setup.sh");
print "*** ", join(' ', @run), "\n";
system(@run) == 0 or die;

die "unfinished, not committing\n" unless -f "$tmpdir/FINI";

sleep 15; # docker container is not always immediately up to a commit, let's give it time to cool off.

open CID, "<$tmpdir/CID" or die;
our $cid = <CID>;
close CID;

our @commit = ( 'sudo', 'docker', 'commit' );
push @commit, "--author=\"$author\"" if defined $author;
# The --change option will apply Dockerfile instructions to the image that is created. Supported Dockerfile instructions: CMD|ENTRYPOINT|ENV|EXPOSE|LABEL|ONBUILD|USER|VOLUME|WORKDIR
for my $k (keys %metadata) {
    my $v = $metadata{$k};

    if ($k eq 'ENV') {
        if (ref $v eq 'ARRAY') {
            for my $env (@$v) {
                push @commit, "--change=\"ENV $env\"";
            }
        }
    } else {
        if (ref $v eq 'ARRAY') {
            my $str = join ',', map { "'$_'" } @$v;
            push @commit, "--change=\"$k $str\"";
        } else {
            push @commit, "--change=\"$k $v\"";
        }
    }
}

push @commit, $cid;
print "*** ", join(' ', @commit), "\n";
my $cmd = join(' ', @commit);
system($cmd);
