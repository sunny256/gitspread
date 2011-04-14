#!/usr/bin/perl

#=======================================================================
# gitspreadd.t
# File ID: aed76eda-6124-11e0-aeaf-adf3f75e27a6
# Test suite for gitspreadd(1).
#
# Character set: UTF-8
# ©opyleft 2011– Øyvind A. Holm <sunny@sunbase.org>
# License: GNU General Public License version 3 or later, see end of 
# file for legal stuff.
#=======================================================================

use strict;
use warnings;

BEGIN {
    # push(@INC, "$ENV{'HOME'}/bin/STDlibdirDTS");
    use Test::More qw{no_plan};
    use_ok('Cwd');
    use_ok('Fcntl');
    use_ok('IO::Handle');
    use_ok('POSIX');
}

use Cwd;
use File::Copy;
use Getopt::Long;

local $| = 1;

our $Debug = 0;
our $CMD = '../gitspreadd';

our %Opt = (

    'all' => 0,
    'debug' => 0,
    'help' => 0,
    'todo' => 0,
    'verbose' => 0,
    'version' => 0,

);

our $progname = $0;
$progname =~ s/^.*\/(.*?)$/$1/;
our $VERSION = '0.01';

Getopt::Long::Configure('bundling');
GetOptions(

    'all|a' => \$Opt{'all'},
    'debug' => \$Opt{'debug'},
    'help|h' => \$Opt{'help'},
    'todo|t' => \$Opt{'todo'},
    'verbose|v+' => \$Opt{'verbose'},
    'version' => \$Opt{'version'},

) || die("$progname: Option error. Use -h for help.\n");

$Opt{'debug'} && ($Debug = 1);
$Opt{'help'} && usage(0);
if ($Opt{'version'}) {
    print_version();
    exit(0);
}

diag(sprintf('========== Executing %s v%s ==========',
    $progname,
    $VERSION));

unless (ok(-e 'gitspreadd.t' && -e '../gitspreadd' && -e '../post-receive',
    'We are in the correct directory')) {
    diag('Has to be run from inside the gitspread/t/ directory.');
    exit 1;
}

if ($Opt{'todo'} && !$Opt{'all'}) {
    goto todo_section;
}

=pod

testcmd("$CMD command", # {{{
    <<'END',
[expected stdin]
END
    '',
    0,
    'description',
);

# }}}

=cut

diag('Testing -h (--help) option...');
likecmd("$CMD -h", # {{{
    '/  Show this help\./',
    '/^$/',
    0,
    'Option -h prints help screen',
);

# }}}
diag('Testing -v (--verbose) option...');
likecmd("$CMD -hv", # {{{
    '/^\n\S+ v\d\.\d\d\n/s',
    '/^$/',
    0,
    'Option --version with -h returns version number and help screen',
);

# }}}
diag('Testing --version option...');
likecmd("$CMD --version", # {{{
    '/^\S+ v\d\.\d\d\n/',
    '/^$/',
    0,
    'Option --version returns version number',
);

# }}}

my $datefmt = '20\d\d-\d\d-\d\d \d\d:\d\d:\d\dZ';

my $SHOULD_NOT_EXIST = 0;
my $SHOULD_EXIST = 1;

my $orig_dir = cwd();
my $tmpdir = "$orig_dir/tmpdir";
my $repo = "$tmpdir/repo.git";
my $mirror = "$tmpdir/mirror.git";
my $hook = "$repo/hooks/post-receive";
my $wrkdir = "$tmpdir/wrkdir";
my $spooldir = "$tmpdir/spool";
my $logfile = "$tmpdir/gitspreadd.log";
my $pidfile = "$tmpdir/pid";
my $stopfile = "$tmpdir/stop";

cleanup();
testcmd("$CMD -1 -r $tmpdir", # {{{
    '',
    "gitspreadd: $tmpdir: Missing repository top directory\n",
    1,
    'Complain about missing repodir',
);

# }}}
create_tmpdir();
likecmd("$CMD -1 -r $tmpdir", # {{{
    '/^Starting gitspreadd v\d.\d\d, PID = \d+\n$/s',
    '/^$/',
    0,
    'Run with -r option',
);

# }}}
ok(-d $spooldir, "$spooldir exists");
ok(-e $logfile, "$logfile exists");
like(file_data($logfile), # {{{
    "/^$datefmt - Starting gitspreadd v\\d.\\d\\d, PID = \\d+\\n\$/s",
    "$logfile looks ok"
);

# }}}
cleanup();
create_tmpdir();
likecmd("GITSPREAD_REPODIR=$tmpdir $CMD -1", # {{{
    '/^Starting gitspreadd v\d.\d\d, PID = \d+\n$/s',
    '/^$/',
    0,
    'Use GITSPREAD_REPODIR environment variable',
);

# }}}
ok(-d $spooldir, "$spooldir exists");
ok(-e $logfile, "$logfile exists");

diag('Set up repositories...');

setup_repo();
setup_wrkdir();
setup_mirror();

start_daemon();

add_and_commit_newfile();
push_to_repo_succeeds();
check_log($SHOULD_EXIST, $mirror, 'Commit exists in mirror.git');

diag('Check gitspread.forcepush config option...');
reset_wrkdir_to_first_commit();
push_to_repo_denied();
push_to_repo_force_update();
check_log($SHOULD_EXIST, $mirror, 'Commit still exists in mirror.git');

enable_gitspread_forcepush();
add_and_commit_newfile();
push_to_repo_succeeds();
reset_wrkdir_to_first_commit();
push_to_repo_force_update();
check_log($SHOULD_NOT_EXIST, $mirror, 'Commit is gone from mirror.git');

stop_daemon();
cleanup();

todo_section:
;

if ($Opt{'all'} || $Opt{'todo'}) {
    diag('Running TODO tests...'); # {{{

    TODO: {

local $TODO = '';
# Insert TODO tests here.

    }
    # TODO tests }}}
}

diag('Testing finished.');

sub cleanup {
    # {{{
    ok(chdir($orig_dir), "chdir $orig_dir");
    testcmd("rm -rf $tmpdir", '', '', 0, 'Delete tmpdir');
    ok(!-e $tmpdir, "$tmpdir does not exist");
    return;
    # }}}
} # cleanup()

sub create_tmpdir {
    # {{{
    ok(mkdir($tmpdir), "mkdir $tmpdir");
    ok(-d $tmpdir, 'tmpdir exists');
    return;
    # }}}
} # create_tmpdir()

sub clone_bundle {
    # {{{
    my ($dir, $bare) = @_;

    my $bare_str = $bare ? " --bare" : "";
    my $bare_msg = $bare ? " bare repository" : "";
    testcmd("git clone$bare_str $orig_dir/repo.bundle $tmpdir/$dir",
        "Cloning into$bare_msg $tmpdir/$dir...\n",
        '',
        0,
        "Clone repo.bundle into $dir"
    );
    return;
    # }}}
} # clone_bundle()

sub setup_repo {
    # {{{
    diag('Create repo.git...');
    testcmd("rm -rf $repo", '', '', 0, 'Make sure repo.git does not exist');
    clone_bundle('repo.git', 1);
    my $bck_dir = cwd();
    ok(chdir($repo), 'chdir repo.git');
    testcmd("git remote add mirror $mirror", '', '', 0, 'Set up mirror remote');
    testcmd("git remote rm origin", '', '', 0, 'Delete origin remote');
    ok(copy("$orig_dir/../post-receive", $hook), "Copy ../post-receive to $hook");
    ok(-e $hook, 'Yes, it was really copied');
    ok(chmod(0755, $hook), "Make $hook executable");
    is((stat($hook))[2] & 07777, 0755, "$hook has correct permissions");
    ok(chdir($bck_dir), 'Return to previous directory');
    return;
    # }}}
} # setup_repo()

sub setup_wrkdir {
    # {{{
    testcmd("rm -rf $wrkdir", '', '', 0, 'Make sure wrkdir does not exist');
    clone_bundle('wrkdir', 0);
    ok(chdir($wrkdir), 'chdir wrkdir');
    testcmd("git remote add dest $repo", '', '', 0, 'Set up dest remote');
    return;
    # }}}
} # setup_wrkdir()

sub setup_mirror {
    # {{{
    testcmd("rm -rf $mirror", '', '', 0, 'Make sure mirror.git does not exist');
    clone_bundle('mirror.git', 1);
    check_log($SHOULD_NOT_EXIST, $mirror, 'The magical commit does not exist in mirror.git yet');
    # }}}
} # setup_mirror()

sub add_and_commit_newfile {
    # {{{
    diag('Make a commit...');
    ok(chdir($wrkdir), "chdir $wrkdir");
    ok(open(my $newfile, '>', 'newfile'), 'Create newfile');
    ok(print($newfile "This file is new.\n"), 'Write to newfile');
    ok(close($newfile), 'Close newfile');
    testcmd('git add newfile', '', '', 0, 'Add newfile for commit');
    likecmd('git commit -m "Adding a great newfile"',
        '/^\[master [0-9a-f].*?\] Adding a great newfile\n.*$/s',
        '/^$/',
        0,
        'Commit addition of newfile'
    );
    return;
    # }}}
} # add_and_commit_newfile()

sub check_log {
    # {{{
    my ($should_exist, $dir, $msg) = @_;
    ok(chdir($dir), "chdir $dir");
    if ($should_exist == $SHOULD_EXIST) {
        like(`git log`, '/^.*Adding a great newfile.*$/s', $msg);
    } else {
        unlike(`git log`, '/^.*Adding a great newfile.*$/s', $msg);
    }
    return;
    # }}}
} # check_log()

sub enable_gitspread_forcepush {
    # {{{
    diag('Enable gitspread.forcepush in repo.git...');
    ok(chdir($repo), 'chdir repo.git');
    likecmd('git config gitspread.forcepush true',
        '/^$/',
        '/^$/',
        0,
        'Enable gitspread.forcepush'
    );
    return;
    # }}}
} # enable_gitspread_forcepush()

sub push_to_repo_succeeds {
    # {{{
    ok(chdir($wrkdir), 'chdir wrkdir');
    likecmd("GITSPREAD_REPODIR=$tmpdir git push dest",
        '/^$/',
        '/^.*' .
            'remote: Spreading repo commits:.*' .
            'remote: a1989e25c8e7c23a3c455731f9433ed0932ec193 ' .
            '[0-9a-f]{40} refs/heads/master.*' .
            'remote: Waiting for spreading to complete\.\.\..*' .
            'remote: Spreading finished.*$/s',
        0,
        'Push to dest remote'
    );
    return;
    # }}}
} # push_to_repo_succeeds()

sub push_to_repo_denied {
    # {{{
    ok(chdir($wrkdir), 'chdir wrkdir');
    likecmd("GITSPREAD_REPODIR=$tmpdir git push dest",
        '/^$/',
        '/^.*' .
        'error: failed to push some refs to .*' .
        'To prevent you from losing history, non-fast-forward updates were rejected.*$/s',
        1,
        'Denied non-fast-forward push'
    );
    return;
    # }}}
} # push_to_repo_denied()

sub push_to_repo_force_update {
    # {{{
    ok(chdir($wrkdir), 'chdir wrkdir');
    likecmd("GITSPREAD_REPODIR=$tmpdir git push -f dest",
        '/^$/',
        '/^.*' .
            'remote: Spreading repo commits:.*' .
            'remote: [0-9a-f]{40} ' .
            'a1989e25c8e7c23a3c455731f9433ed0932ec193 refs/heads/master.*' .
            'remote: Waiting for spreading to complete\.\.\..*' .
            'remote: Spreading finished.*' .
            '\.\.\.a1989e2 master -> master \(forced update\).*$/s',
        0,
        'Force-push to dest remote'
    );
    return;
    # }}}
} # push_to_repo_force_update()

sub reset_wrkdir_to_first_commit {
    # {{{
    ok(chdir($wrkdir), 'chdir wrkdir');
    likecmd('git reset --hard a1989e2',
        '/^HEAD is now at a1989e2 Initial empty commit\n$/',
        '/^$/',
        0,
        'Reset HEAD to first commit'
    );
    return;
    # }}}
} # reset_wrkdir_to_first_commit()

sub start_daemon {
    # {{{
    diag('Starting daemon...');
    system("$orig_dir/$CMD -r $tmpdir");
    ok(-e $pidfile, 'PID file exists');
    like(file_data($pidfile), '/^\d+\n$/s', 'PID file looks ok');
    return;
    # }}}
} # start_daemon()

sub stop_daemon {
    # {{{
    diag('Stopping daemon...');
    ok(open(my $stopfh, '>', $stopfile), "Create stop file $stopfile");
    ok(close($stopfh), 'Close stop file');
    diag('Waiting for process to stop...');
    while(-e $stopfile) { }
    ok(!-e $pidfile, 'PID file is removed');
    return;
    # }}}
} # stop_daemon()

sub testcmd {
    # {{{
    my ($Cmd, $Exp_stdout, $Exp_stderr, $Exp_retval, $Desc) = @_;
    my $stderr_cmd = '';
    my $deb_str = $Opt{'debug'} ? ' --debug' : '';
    my $Txt = join('',
        "\"$Cmd\"",
        defined($Desc)
            ? " - $Desc"
            : ''
    );
    my $TMP_STDERR = 'gitspreadd-stderr.tmp';

    if (defined($Exp_stderr) && !length($deb_str)) {
        $stderr_cmd = " 2>$TMP_STDERR";
    }
    is(`$Cmd$deb_str$stderr_cmd`, $Exp_stdout, $Txt);
    my $ret_val = $?;
    if (defined($Exp_stderr)) {
        if (!length($deb_str)) {
            is(file_data($TMP_STDERR), $Exp_stderr, "$Txt (stderr)");
            unlink($TMP_STDERR);
        }
    } else {
        diag("Warning: stderr not defined for '$Txt'");
    }
    is($ret_val >> 8, $Exp_retval, "$Txt (retval)");
    return;
    # }}}
} # testcmd()

sub likecmd {
    # {{{
    my ($Cmd, $Exp_stdout, $Exp_stderr, $Exp_retval, $Desc) = @_;
    my $stderr_cmd = '';
    my $deb_str = $Opt{'debug'} ? ' --debug' : '';
    my $Txt = join('',
        "\"$Cmd\"",
        defined($Desc)
            ? " - $Desc"
            : ''
    );
    my $TMP_STDERR = 'gitspreadd-stderr.tmp';

    if (defined($Exp_stderr) && !length($deb_str)) {
        $stderr_cmd = " 2>$TMP_STDERR";
    }
    like(`$Cmd$deb_str$stderr_cmd`, "$Exp_stdout", $Txt);
    my $ret_val = $?;
    if (defined($Exp_stderr)) {
        if (!length($deb_str)) {
            like(file_data($TMP_STDERR), "$Exp_stderr", "$Txt (stderr)");
            unlink($TMP_STDERR);
        }
    } else {
        diag("Warning: stderr not defined for '$Txt'");
    }
    is($ret_val >> 8, $Exp_retval, "$Txt (retval)");
    return;
    # }}}
} # likecmd()

sub file_data {
    # Return file content as a string {{{
    my $File = shift;
    my $Txt;
    if (open(my $fp, '<', $File)) {
        local $/ = undef;
        $Txt = <$fp>;
        close($fp);
        return($Txt);
    } else {
        return;
    }
    # }}}
} # file_data()

sub print_version {
    # Print program version {{{
    print("$progname v$VERSION\n");
    return;
    # }}}
} # print_version()

sub usage {
    # Send the help message to stdout {{{
    my $Retval = shift;

    if ($Opt{'verbose'}) {
        print("\n");
        print_version();
    }
    print(<<"END");

Usage: $progname [options] [file [files [...]]]

Contains tests for the gitspreadd(1) program.

Options:

  -a, --all
    Run all tests, also TODOs.
  -h, --help
    Show this help.
  -t, --todo
    Run only the TODO tests.
  -v, --verbose
    Increase level of verbosity. Can be repeated.
  --version
    Print version information.
  --debug
    Print debugging messages.

END
    exit($Retval);
    # }}}
} # usage()

sub msg {
    # Print a status message to stderr based on verbosity level {{{
    my ($verbose_level, $Txt) = @_;

    if ($Opt{'verbose'} >= $verbose_level) {
        print(STDERR "$progname: $Txt\n");
    }
    return;
    # }}}
} # msg()

__END__

# Plain Old Documentation (POD) {{{

=pod

=head1 NAME

run-tests.pl

=head1 SYNOPSIS

gitspreadd.t [options] [file [files [...]]]

=head1 DESCRIPTION

Contains tests for the gitspreadd(1) program.

=head1 OPTIONS

=over 4

=item B<-a>, B<--all>

Run all tests, also TODOs.

=item B<-h>, B<--help>

Print a brief help summary.

=item B<-t>, B<--todo>

Run only the TODO tests.

=item B<-v>, B<--verbose>

Increase level of verbosity. Can be repeated.

=item B<--version>

Print version information.

=item B<--debug>

Print debugging messages.

=back

=head1 AUTHOR

Made by Øyvind A. Holm S<E<lt>sunny@sunbase.orgE<gt>>.

=head1 COPYRIGHT

Copyleft © Øyvind A. Holm E<lt>sunny@sunbase.orgE<gt>
This is free software; see the file F<COPYING> for legalese stuff.

=head1 LICENCE

This program is free software: you can redistribute it and/or modify it 
under the terms of the GNU General Public License as published by the 
Free Software Foundation, either version 3 of the License, or (at your 
option) any later version.

This program is distributed in the hope that it will be useful, but 
WITHOUT ANY WARRANTY; without even the implied warranty of 
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along 
with this program.
If not, see L<http://www.gnu.org/licenses/>.

=head1 SEE ALSO

=cut

# }}}

# vim: set fenc=UTF-8 ft=perl fdm=marker ts=4 sw=4 sts=4 et fo+=w :
