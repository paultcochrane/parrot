#! perl
# Copyright (C) 2010, Parrot Foundation.
# $Id$
# 01_functions.t

use strict;
use warnings;
use Test::More qw(no_plan); # tests => 38;
use Carp;
use Cwd;
use File::Copy;
use File::Path qw( mkpath );
use File::Spec;
use File::Temp qw( tempdir );
use lib qw( lib );
use Parrot::Config;
use Parrot::Headerizer::Functions qw(
    process_argv
    read_file
    write_file
    qualify_sourcefile
    asserts_from_args
    shim_test
    handle_modified_args
    add_newline_if_multiline
    add_asserts_to_declarations
    func_modifies
    add_headerizer_markers
);

use IO::CaptureOutput qw| capture |;

my $cwd = cwd();
my @ofiles;

# process_argv()
eval {
    @ofiles = process_argv();
};
like($@, qr/No files specified/,
    "Got expected error message for no files specified");

@ofiles = qw( alpha.o beta.o gamma.o alpha.o );
{
    my ($stdout, $stderr);
    capture(
        sub { @ofiles = process_argv(@ofiles); },
        \$stdout,
        \$stderr,
    );
    is(@ofiles, 3, "Got expected number of ofiles");
    like( $stdout,
        qr/alpha\.o is specified more than once/s,
        "Got expected message for an argument supplied more than once"
    );
}

@ofiles = qw( alpha.o beta.o gamma.o );
is(@ofiles, 3, "Got expected number of ofiles");

# read_file; write_file
{
    my $tdir = tempdir( CLEANUP => 1 );
    chdir $tdir;
    my $file = "filename$$";
    my @lines_to_write = (
        "Goodbye\n",
        "cruel\n",
        "world\n",
    );
    my $text = join( '' => @lines_to_write );
    write_file($file, $text);
    ok(-f $file, "File was written");

    my $text_returned = read_file($file);
    ok($text_returned, "Got non-empty string back from read_file()");
    my @lines_read = split /\n/, $text_returned;
    is($lines_read[0], 'Goodbye', "Got first line");
    is($lines_read[1], 'cruel', "Got second line");
    is($lines_read[2], 'world', "Got third line");
    chdir $cwd or die "Unable to chdir: $!";
}
    
my $filename = 'foobar';
eval {
    read_file($filename);
};
like($@, qr/couldn't read '$filename'/, "Got expected error message for read_file()");

# qualify_sourcefile()
my ($ofile, $is_yacc);
my ($sourcefile, $source_code, $hfile);
$ofile = 'foobar.xyz';
eval {
    my ($sourcefile, $source_code, $hfile) =
        qualify_sourcefile( {
            ofile           => $ofile,
            PConfig         => \%PConfig,
            is_yacc         => 0,
        } );
};
like($@, qr/$ofile doesn't look like an object file/,
    "Got expected die message for non-object, non-yacc file" );
    
# Testing Needs We don't really need a .o file, we just need its name.
# However, we do need one .c file and one .pmc file.  In order to have the
# codingstd tests skip these, we should name them .in and then copy them into
# position with the extensions we need.  We need one file where there is no
# HEADERIZER HFILE directive within the file.  We need a case where the
# HEADERIZER HFILE directive contains 'none'.  We need a case where the header
# file exists and one where it does not.

{
    my $tdir = tempdir( CLEANUP => 1 );
    my $stub = 'lack_directive';
    copy "$cwd/t/tools/dev/headerizer/testlib/$stub.in" =>
         "$tdir/$stub.c" or croak "Unable to copy file for testing";
    $ofile = "$tdir/$stub.o";
    my $expected_cfile = "$tdir/$stub.c";
    eval {
        my ($sourcefile, $source_code, $hfile) =
            qualify_sourcefile( {
                ofile           => $ofile,
                PConfig         => \%PConfig,
                is_yacc         => 0,
            } );
    };
    like($@, qr/can't find HEADERIZER HFILE directive in "$expected_cfile"/,
        "Got expected die message for file lacking HEADERIZER HFILE directive" );
}

{
    my $tdir = tempdir( CLEANUP => 1 );
    my $stub = 'none';
    copy "$cwd/t/tools/dev/headerizer/testlib/$stub.in" =>
         "$tdir/$stub.c" or croak "Unable to copy file for testing";
    $ofile = "$tdir/$stub.o";
    my $expected_cfile = "$tdir/$stub.c";
    my ($sourcefile, $source_code, $hfile) =
        qualify_sourcefile( {
            ofile           => $ofile,
            PConfig         => \%PConfig,
            is_yacc         => 0,
        } );
    is( $sourcefile, $expected_cfile, "Got expected C source file" );
    like( $source_code, qr/This file has 'none'/, 
        "Got expected source code" );
    is( $hfile, 'none', "As expected, no header file" );
}

{
    my $tdir = tempdir( CLEANUP => 1 );
    my $stub = 'missingheaderfile';
    copy "$cwd/t/tools/dev/headerizer/testlib/$stub.in" =>
         "$tdir/$stub.c" or croak "Unable to copy file for testing";
    $ofile = "$tdir/$stub.o";
    my $expected_cfile = "$tdir/$stub.c";
    eval {
        my ($sourcefile, $source_code, $hfile) =
            qualify_sourcefile( {
                ofile           => $ofile,
                PConfig         => \%PConfig,
                is_yacc         => 0,
            } );
    };
    like($@, qr/"$stub" not found \(referenced from "$expected_cfile"\)/,
        "Got expected error message for missing header file" );
}

{
    my $tdir = tempdir( CLEANUP => 1 );
    my $stub = 'validheader';
    copy "$cwd/t/tools/dev/headerizer/testlib/$stub.in" =>
         "$tdir/$stub.c" or croak "Unable to copy file for testing";
    copy "$cwd/t/tools/dev/headerizer/testlib/h$stub.in" =>
         "$tdir/$stub.h" or croak "Unable to copy file for testing";
    $ofile = "$tdir/$stub.o";
    my $expected_cfile = "$tdir/$stub.c";
    chdir $tdir;
    my ($sourcefile, $source_code, $hfile) =
        qualify_sourcefile( {
            ofile           => $ofile,
            PConfig         => \%PConfig,
            is_yacc         => 0,
        } );
    chdir $cwd;
    is( $sourcefile, $expected_cfile, "Got expected C source file" );
    like( $source_code, qr/This file has a valid HEADERIZER HFILE/, 
        "Got expected source code" );
    is( $hfile, "$stub.h", "Got expected header file" );
}

{
    my $tdir = tempdir( CLEANUP => 1 );
    my $stub = 'validheader';
    copy "$cwd/t/tools/dev/headerizer/testlib/$stub.in" =>
         "$tdir/$stub.pmc" or croak "Unable to copy file for testing";
    copy "$cwd/t/tools/dev/headerizer/testlib/h$stub.in" =>
         "$tdir/$stub.h" or croak "Unable to copy file for testing";
    $ofile = "$tdir/$stub.o";
    my $expected_cfile = "$tdir/$stub.pmc";
    chdir $tdir;
    my ($sourcefile, $source_code, $hfile) =
        qualify_sourcefile( {
            ofile           => $ofile,
            PConfig         => \%PConfig,
            is_yacc         => 0,
        } );
    chdir $cwd;
    is( $sourcefile, $expected_cfile, "Got expected PMC file" );
    like( $source_code, qr/This file has a valid HEADERIZER HFILE/, 
        "Got expected source code" );
    is( $hfile, "$stub.h", "Got expected header file" );
}

{
    my $tdir = tempdir( CLEANUP => 1 );
    my $stub = 'imcc';
    copy "$cwd/t/tools/dev/headerizer/testlib/$stub.in" =>
         "$tdir/$stub.y" or croak "Unable to copy file for testing";
    $ofile = "$tdir/$stub.y";
    my $expected_cfile = $ofile;
    my ($sourcefile, $source_code, $hfile) =
        qualify_sourcefile( {
            ofile           => $ofile,
            PConfig         => \%PConfig,
            is_yacc         => 1,
        } );
    is( $sourcefile, $expected_cfile, "Got expected C source file" );
    like( $source_code, qr/HEADERIZER HFILE: none/, "Got expected source code" );
    is( $hfile, 'none', "As expected, no header file" );
}

# asserts_from_args()
my (@args, %asserts);
@args = (
    'SHIM_INTERP',
    'ARGIN(Linked_List *list)',
    'ARGIN(List_Item_Header *item)',
);
%asserts = map { $_ => 1 } asserts_from_args( @args );
is( keys %asserts, 2, "Got expected number of asserts" );
ok( exists $asserts{'PARROT_ASSERT_ARG(list)'}, "Got expected assert" );
ok( exists $asserts{'PARROT_ASSERT_ARG(item)'}, "Got expected assert" );

@args = (
    'PARROT_INTERP',
    'ARGIN(Linked_List *list)',
    'ARGIN(List_Item_Header *item)',
    'SHIM_INTERP',
);
%asserts = map { $_ => 1 } asserts_from_args( @args );
is( keys %asserts, 3, "Got expected number of asserts" );
ok( exists $asserts{'PARROT_ASSERT_ARG(list)'}, "Got expected assert" );
ok( exists $asserts{'PARROT_ASSERT_ARG(item)'}, "Got expected assert" );
ok( exists $asserts{'PARROT_ASSERT_ARG(interp)'}, "Got expected assert" );

@args = (
    'ARGFREE_NOTNULL(( _abcDEF123 )())',
    'PARROT_INTERP',
    'ARGIN(Linked_List *list)',
    'ARGIN(List_Item_Header *item)',
    'SHIM_INTERP',
);
%asserts = map { $_ => 1 } asserts_from_args( @args );
is( keys %asserts, 4, "Got expected number of asserts" );
ok( exists $asserts{'PARROT_ASSERT_ARG(list)'}, "Got expected assert" );
ok( exists $asserts{'PARROT_ASSERT_ARG(item)'}, "Got expected assert" );
ok( exists $asserts{'PARROT_ASSERT_ARG(interp)'}, "Got expected assert" );
ok( exists $asserts{'PARROT_ASSERT_ARG(_abcDEF123)'}, "Got expected assert" );

my ($var, $args_ref, $funcs_ref, $expected);
my @modified_args;
# shim_test
$var = 'something';
$args_ref =  [
    "SHIM($var)",
    'ARGIN(STRING *sig)',
];
$funcs_ref =  {
    'macros' => [],
    'return_type' => 'void',
    'is_api' => undef,
    'is_inline' => undef,
    'is_static' => 'static',
    'args' => $args_ref,
    'name' => 'pcc_params',
    'file' => 'src/pmc/nci.c',
    'is_ignorable' => 0
};
$expected = [
    "SHIM($var)",
    $args_ref->[1],
];
@modified_args = shim_test($funcs_ref, $args_ref);
is_deeply( [ @modified_args ], $expected,
    "Got expected args back from shim_test()" );

$var = 'something *else';
$args_ref =  [
    "SHIM($var)",
    'ARGIN(STRING *sig)',
];
$funcs_ref =  {
    'macros' => [],
    'return_type' => 'void',
    'is_api' => undef,
    'is_inline' => undef,
    'is_static' => undef,
    'args' => $args_ref,
    'name' => 'pcc_params',
    'file' => 'src/pmc/nci.c',
    'is_ignorable' => 0
};
$expected = [
    "SHIM($var)",
    $args_ref->[1],
];
@modified_args = shim_test($funcs_ref, $args_ref);
is_deeply( [ @modified_args ], $expected,
    "Got expected args back from shim_test()" );

$var = 'something';
$args_ref =  [
    "SHIM($var)",
    'ARGIN(STRING *sig)',
];
$funcs_ref =  {
    'macros' => [],
    'return_type' => 'void',
    'is_api' => undef,
    'is_inline' => undef,
    'is_static' => undef,
    'args' => $args_ref,
    'name' => 'pcc_params',
    'file' => 'src/pmc/nci.c',
    'is_ignorable' => 0
};
$expected = [
    "NULLOK($var)",
    $args_ref->[1],
];
@modified_args = shim_test($funcs_ref, $args_ref);
is_deeply( [ @modified_args ], $expected,
    "Got expected args back from shim_test()" );

$var = 'something';
$args_ref =  [
    "SHAM($var)",
    'ARGIN(STRING *sig)',
];
$funcs_ref =  {
    'macros' => [],
    'return_type' => 'void',
    'is_api' => undef,
    'is_inline' => undef,
    'is_static' => undef,
    'args' => $args_ref,
    'name' => 'pcc_params',
    'file' => 'src/pmc/nci.c',
    'is_ignorable' => 0
};
$expected = $args_ref;
@modified_args = shim_test($funcs_ref, $args_ref);
is_deeply( [ @modified_args ], $expected,
    "Got expected args back from shim_test()" );

# handle_modified_args()
my ($decl_in, $decl_out, $multiline);

$decl_in = 'void Parrot_list_append(';
@modified_args = qw( alpha beta gamma );
($decl_out, $multiline) = handle_modified_args(
    $decl_in, \@modified_args);
is( $decl_out, $decl_in . 'alpha, beta, gamma)',
    "Got expected portion of declaration (short)" );
ok( ! $multiline, "Short portion of declaration means no multiline" );

$decl_in = 'void Parrot_list_append(';
@modified_args = (
  'FOOBAR EXTRAORDINARY',
  'ARGMOD(Linked_List *list)',
  'ARGMOD(List_Item_Header *item)',
);
$expected = $decl_in .
    "\n\t$modified_args[0]" . ',' .
    "\n\t$modified_args[1]" . ',' .
    "\n\t$modified_args[2]" . ')';
($decl_out, $multiline) = handle_modified_args(
    $decl_in, \@modified_args);
is( $decl_out, $expected,
    "Got expected portion of declaration (long)" );
ok( $multiline, "Long portion of declaration means multiline" );

$decl_in = 'void Parrot_list_append(';
@modified_args = (
  'SHIM_INTERP',
  'ARGMOD(Linked_List *list)',
  'ARGMOD(List_Item_Header *item)',
);
$expected = $decl_in .
    $modified_args[0] . ',' .
    "\n\t$modified_args[1]" . ',' .
    "\n\t$modified_args[2]" . ')';
($decl_out, $multiline) = handle_modified_args(
    $decl_in, \@modified_args);
is( $decl_out, $expected,
    "Got expected portion of declaration (long SHIM)" );
ok( $multiline, "Long portion of declaration means multiline" );

$decl_in = 'void Parrot_list_append(';
@modified_args = (
  'SHIM_INTERP INCURABLY_EXTREMELY_EXTRAORDINARILY_ARGMOD(Linked_List *list)',
);
$expected = "$decl_in$modified_args[0])";
($decl_out, $multiline) = handle_modified_args(
    $decl_in, \@modified_args);
is( $decl_out, $expected,
    "Got expected portion of declaration (long SHIM one arg)" );
ok( $multiline, "Long portion of declaration means multiline" );

# add_newline_if_multiline()
$decl_in = 'alpha';
$multiline = 1;
$decl_out = add_newline_if_multiline($decl_in, $multiline);
is( $decl_out, "alpha;\n",
    "Got expected value from add_newline_if_multiline()" );

$decl_in = 'alpha';
$multiline = 0;
$decl_out = add_newline_if_multiline($decl_in, $multiline);
is( $decl_out, "alpha;",
    "Got expected value from add_newline_if_multiline()" );


# add_asserts_to_declarations()
$funcs_ref = [
  {
    'macros' => [
      'PARROT_EXPORT'
    ],
    'return_type' => 'void',
    'is_api' => 1,
    'is_inline' => undef,
    'is_static' => undef,
    'args' => [
      'SHIM_INTERP',
      'ARGMOD(Linked_List *list)',
      'ARGMOD(List_Item_Header *item)'
    ],
    'name' => 'Parrot_list_append_and_append_and_append',
    'file' => 'src/list.c',
    'is_ignorable' => 0
  },
];
my $decls_ref = [];
my @decls = add_asserts_to_declarations($funcs_ref, $decls_ref);
$expected = <<'EXP';
#define ASSERT_ARGS_Parrot_list_append_and_append_and_append \
     __attribute__unused__ int _ASSERT_ARGS_CHECK = (\
       PARROT_ASSERT_ARG(list) \
EXP
$expected .= '    , PARROT_ASSERT_ARG(item))';
is( $decls[0], $expected,
    "Got expected declaration from add_asserts_to_declarations()" );

# func_modifies()
my ($arg, @mods, @mods_out);
$arg = 'ARGMOD(List_Item_Header *item)';
@mods = ( 'FUNC_MODIFIES(*list)' );
$expected = [
    'FUNC_MODIFIES(*list)',
    'FUNC_MODIFIES(*item)',
];
@mods_out = func_modifies($arg, \@mods);
is_deeply( \@mods_out, $expected,
    "Got expected output of func_modifies()" );

$arg = 'foobar';
@mods = ( 'FUNC_MODIFIES(*list)' );
$expected = [
    'FUNC_MODIFIES(*list)',
];
@mods_out = func_modifies($arg, \@mods);
is_deeply( \@mods_out, $expected,
    "Got expected output of func_modifies()" );

$arg = 'ARGMOD_NULLOK(List_Item_Header alpha)';
@mods = ( 'FUNC_MODIFIES(*list)' );
$expected = [
    'FUNC_MODIFIES(*list)',
    'FUNC_MODIFIES(alpha)',
];
@mods_out = func_modifies($arg, \@mods);
is_deeply( \@mods_out, $expected,
    "Got expected output of func_modifies()" );

eval {
   $arg = 'ARGMOD_NULLOK(List_Item_Header)';
   @mods = ( 'FUNC_MODIFIES(*list)' );
   $expected = [
       'FUNC_MODIFIES(*list)',
       'FUNC_MODIFIES(alpha)',
   ];
   @mods_out = func_modifies($arg, \@mods);
};
like($@, qr/Unable to figure out the modified/,
    "Got expected error message for func_modifies()" );


# add_headerizer_markers
#{
#    my $tdir = tempdir( CLEANUP => 1 );
#    chdir $tdir or croak "Unable to chdir during testing";
#
#    my $stub = 'list';
#    my $srcdir    = File::Spec->catpath( $tdir, 'src' );
#    mkpath( $srcdir, 0, 0777 );
#    my $srco      = File::Spec->catfile( $srcdir, "$stub.o" );
#    touchfile($srco);
#    my $srcc      = File::Spec->catfile( $srcdir, "$stub.c" );
#    copy "$cwd/t/tools/dev/headerizer/testlib/list.in" => $srcc
#        or croak "Unable to copy";
#    my $incdir    = File::Spec->catpath( $tdir, 'include', 'parrot' );
#    mkpath( $incdir, 0, 0777 );
#    my $inch      = File::Spec->catfile( $incdir, "$stub.h" );
#    copy "$cwd/t/tools/dev/headerizer/testlib/list_h.in" => $inch
#        or croak "Unable to copy";
#
#    my $source_code = read_file($srcc);
#    my $function_decls_file = "$tdir/function_decls";
#    copy "$cwd/t/tools/dev/headerizer/testlib/function_decls.in" =>
#        $function_decls_file or croak "Unable to copy";
#    my $intext = read_file($function_decls_file);
#    my @function_decls;
#    ( @function_decls ) = $intext =~ m/'([^,][^']*?)'/gs;
#
# TEST IS NOT SET UP PROPERLY YET.
#
#    my $headerized_source =  add_headerizer_markers( {
#        function_decls  => \@function_decls,
#        sourcefile      => $srcc,
#        hfile           => $inch,
#        code            => $source_code,
#    } );
#print STDERR $headerized_source;
#
#    chdir $cwd or croak "Unable to chdir back after testing";
#}

pass("Completed all tests in $0");

sub touchfile {
    my $filename = shift;
    open my $IN, '>', $filename or croak "Unable to open for writing";
    print $IN "\n";
    close $IN or croak "Unable to close after writing";
    return 1;
}

################### DOCUMENTATION ###################

=head1 NAME

01_functions.t - Test functions in Parrot::Headerizer::Functions.

=head1 SYNOPSIS

    % prove t/tools/dev/headerizer/01_functions.t

=head1 DESCRIPTION

The files in this directory test the publicly callable subroutines found in 
F<lib/Parrot/Headerizer/Functions.pm>.  By doing so, they help test the functionality
of the F<tools/dev/headerizer.pl> utility.


=head1 AUTHOR

James E Keenan

=head1 SEE ALSO

F<tools/dev/headerizer.pl>; F<lib/Parrot/Headerizer/Functions.pm>.

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
