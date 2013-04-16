# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl SVN-Access.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

#use Test::More tests => 1;
use Test::More qw(no_plan); # replace this later.

BEGIN { use_ok('SVN::Access') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

# create a new file.
my $acl = SVN::Access->new(acl_file => 'svn_access_test.conf');
$acl->add_group('@folks', 'bob', 'ed', 'frank');

is(scalar($acl->group('folks')->members), 3, "Added new group to the object.");
$acl->add_resource('/', '@folks', 'rw');
is($acl->resource('/')->authorized->{'@folks'}, 'rw', "Make sure we added these folks to the '/' resource.");
$acl->write_acl;

$acl->add_resource('/test');
is(ref($acl->resource('/test')), 'SVN::Access::Resource', "Do empty resources show up in the array?");
$acl->write_acl;

$acl = SVN::Access->new(acl_file => 'svn_access_test.conf');
is(ref($acl->resource('/test')), 'SVN::Access::Resource', "Do empty resources show up in the array after re-parsing the file?");

$acl->add_resource('repo:/something with spaces', mike => 'rw');

$acl->add_resource('/kagetest', 
    joey => 'rw',
    billy => 'r',
    sam => 'r',
);

$acl->resource('/kagetest')->authorize(
    judy => 'rw',
    phil => 'r',
    frank => '',
    wanda => 'r'
);

$acl->resource('/kagetest')->authorize(sammy => 'r', 2);

# add / remove aliases test
$acl->add_alias('mikey', 'uid=mgregorowicz,ou=people,dc=mg2,dc=org'); 
is($acl->alias('mikey'), 'uid=mgregorowicz,ou=people,dc=mg2,dc=org', "Making sure we can add an alias.");
$acl->remove_alias('mikey');
is($acl->alias('mikey'), undef, "Delete alias check.");

# putting the alias back after the roundtrip test
$acl->add_alias('mikey', 'uid=mgregorowicz,ou=people,dc=mg2,dc=org');

$acl->write_acl;

my $whitespace_at_end_test = <<EOF;
[aliases]
mikey = uid=mgregorowicz,ou=people,dc=mg2,dc=org

[groups]
folks = bob, ed, frank

[/]
\@folks = rw

[/test]

[repo:/something with spaces]
mike = rw

[/kagetest]
joey = rw
billy = r
sammy = r
sam = r
judy = rw
phil = r
frank = 
wanda = r
EOF

chomp($whitespace_at_end_test); # no newline here!
$whitespace_at_end_test .= "          "; # <- have some whitespace!
open(WSTEST, '>', 'whitespace_at_end_test.conf');
print WSTEST $whitespace_at_end_test;
close(WSTEST);
my $wstestacl = SVN::Access->new(acl_file => 'whitespace_at_end_test.conf');
is(scalar($wstestacl->group('folks')->members), 3, "Sanity checking our whitespace test.");
is($wstestacl->resource('/kagetest')->authorized->{wanda}, 'r', "Making sure there's no trailing whitespace after wanda's 'r' access.");

# cleanup whitespace check...
unlink('whitespace_at_end_test.conf');

my $test_contents = <<EOF;
[aliases]
mikey = uid=mgregorowicz,ou=people,dc=mg2,dc=org

[groups]
folks = bob, ed, frank

[/]
\@folks = rw

[/test]

[repo:/something with spaces]
mike = rw

[/kagetest]
joey = rw
billy = r
sammy = r
sam = r
judy = rw
phil = r
frank = 
wanda = r

EOF

my $actual_contents;
open(TEST_ACL, '<', 'svn_access_test.conf');
{
    local $/;
    $actual_contents = <TEST_ACL>;
}

is($actual_contents, $test_contents, "Making sure our output remains in-order.");

$acl = SVN::Access->new(acl_file => 'svn_access_test.conf');
is(scalar($acl->group('folks')->members), 3, "Checking our group after the write-out.");
$acl->remove_group('folks');
is(defined($acl->groups), '', "Making sure groups is undefined when we delete the last one");

# Aliases added at Trent Fisher's request, tested here...
is($acl->aliases->{mikey}, 'uid=mgregorowicz,ou=people,dc=mg2,dc=org', "Does my alias still exist after round trip?");

# use the name => notation...
$acl->add_resource(
    name => '/awesomeness',
    authorized => {
        mike => 'rw',
    }
);

# Jesse Thompson's verify_acl tests
$acl->add_resource('/new', '@doesntexist', 'rw');
eval {
    $acl->write_acl;
};
ok(defined($@), 'We encountered a fatal error when trying to write an erroneous ACL.');
# save future writes the grief
$acl->remove_resource('/new');

# little bit of testing for Matt Smith's new regex.
$acl->add_resource('my-repo:/test/path', 'mikey_g',  'rw');
is($acl->resource('my-repo:/test/path')->authorized->{mikey_g}, 'rw', 'Can we call up perms on the new path?');
$acl->remove_resource('/');

# Matt's regex is updated now.. we are allowed to have spaces in ACLs
$acl->add_resource('my-repo2:/this/that/the other/thing');
$acl->write_acl;

$acl = SVN::Access->new(acl_file => 'svn_access_test.conf');
$acl->remove_resource('/test');
$acl->remove_resource('my-repo:/test/path');
$acl->remove_resource('/kagetest');
$acl->remove_resource('my-repo2:/this/that/the other/thing');
$acl->remove_resource('repo:/something with spaces');
$acl->remove_resource('/awesomeness');
$acl->remove_alias('mikey');

is(defined($acl->resources), '', "Making sure resources is undefined when we delete the last one");
$acl->write_acl;

# the config file should be empty now.. so lets clean up if it is
is((stat('svn_access_test.conf'))[7], 0, "Making sure our SVN ACL file is zero bytes, and unlinking.");
system("cat svn_access_test.conf");
unlink('svn_access_test.conf');

# test for line continuations and trailing comments
open(LTEST, '>', 'line_cont.conf');
print LTEST <<'CHUMBA';
[groups]
folks = bob, 
 ed,
	frank
missing=not
  
# the line above contains some whitespace
foo=bar # not allowed, baz
# see libsvn_subr/config_file.c:svn_config__parse_file()
[/]
@folks = rw

CHUMBA
#/];# (keep emacs perl-mode happy)
close(LTEST);

$acl = SVN::Access->new(acl_file => 'line_cont.conf');
ok(defined($acl), "Make sure we can parse file with line continuations");
my @m = $acl->group('folks')->members;
is($#m, 2, "Make sure group has three members, via continuations");
is($m[2], "frank", "Make sure frank is at the end of the list");

# check the trailing comment
@m = $acl->group('foo')->members;
is($#m, 1, "Make sure group has 2 members");
is($m[0], "bar # not allowed", "make sure comment is appended as svn does");
is($m[1], "baz", "make sure next entry is right");

# check for handling lines with whitespace... they should not get treated as
# line continuations
is(ref $acl->group('missing'), "SVN::Access::Group",
   "Group before bogus line continuation should be present");

unlink('line_cont.conf');

