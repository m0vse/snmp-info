# My::Test::Class
#
# Copyright (c) 2018 Eric Miller
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the University of California, Santa Cruz nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR # ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

package My::Test::Class;

use Test::Class::Most attributes => [qw/class mock_session test_obj/];
use Test::MockObject::Extends;
use File::Find 'find';
use Path::Class 'dir';
use File::Slurper 'read_lines';

use base qw<Test::Class Class::Data::Inheritable>;

# Don't run the base tests defined in this class, run them in subclasses only
My::Test::Class->SKIP_CLASS( 1 );

INIT { Test::Class->runtests }

my $EMPTY = q{};

sub startup : Tests( startup => 1 ) {
  my $test = shift;
  (my $class = ref $test) =~ s/^Test:://x;
  return ok 1, "$class loaded" if $class eq __PACKAGE__;
  use_ok $class or die;
  $test->class($class);
  $test->mock_session(create_mock_session());
  return;
}

sub shutdown : Tests(shutdown) { }

sub setup : Tests(setup) {
  my $test  = shift;
  my $class = $test->class;
  my $sess  = $test->mock_session;

  $test->{info} = $class->new(
    'AutoSpecify' => 0,
    'BulkWalk'    => 0,
    'UseEnums'    => 1,
    'RetryNoSuch' => 1,
    'DestHost'    => '127.0.0.1',
    'Community'   => 'public',
    'Version'     => 2,
    'Session'     => $sess,
  );
}

sub teardown : Tests(teardown) {
  my $test = shift;
  my $sess = $test->mock_session;

  # Make sure we start clear object and any mocked session data after each test
  $test->{info} = undef;
  $sess->{Data} = {};
}

sub constructor : Tests(8) {
  my $test  = shift;
  my $class = $test->class;

  can_ok $class, 'new';
  isa_ok $test->{info}, $class, '... and the object it returns';

  is(defined $test->{info}{init}, 1, 'MIBs initialized');
  ok(
    scalar keys %{$test->{info}{mibs}},
    'MIBs subclass data structure initialized'
  );
  ok(
    scalar keys %{$test->{info}{globals}},
    'Globals subclass data structure initialized'
  );
  ok(
    scalar keys %{$test->{info}{funcs}},
    'Funcs subclass data structure initialized'
  );
  ok(
    scalar keys %{$test->{info}{munge}},
    'Munge subclass data structure initialized'
  );
  is_deeply($test->{info}{store}, {}, 'Store initialized');
}

sub globals : Tests(2) {
  my $test = shift;

  can_ok($test->{info}, 'globals');

  subtest 'Globals can() subtest' => sub {

    my $test_globals = $test->{info}->globals;
    foreach my $key (keys %$test_globals) {
      can_ok($test->{info}, $key);
    }
  };
}

sub funcs : Tests(2) {
  my $test = shift;

  can_ok($test->{info}, 'funcs');

  subtest 'Funcs can() subtest' => sub {

    my $test_funcs = $test->{info}->funcs;
    foreach my $key (keys %$test_funcs) {
      can_ok($test->{info}, $key);
    }
  };
}

sub mibs : Tests(2) {
  my $test = shift;

  can_ok($test->{info}, 'mibs');

  subtest 'MIBs loaded subtest' => sub {

    my $mibs = $test->{info}->mibs();

    foreach my $key (keys %$mibs) {
      my $qual_name = "$key" . '::' . "$mibs->{$key}";
      ok(defined $SNMP::MIB{$mibs->{$key}}, "$qual_name defined");
      like(SNMP::translateObj($qual_name),
        qr/^(\.\d+)+$/, "$qual_name translates to a OID");
    }
  };
}

sub munge : Tests(2) {
  my $test = shift;

  can_ok($test->{info}, 'munge');

  subtest 'Munges subtest' => sub {

    my $test_munges = $test->{info}->munge();
    foreach my $key (keys %$test_munges) {
      isa_ok($test_munges->{$key}, 'CODE', "$key munge");
    }
  };
}

#
# Utility methods / functions
#

sub create_mock_session {

  my $home = dir($ENV{HOME}, 'netdisco-mibs');

  local $ENV{'SNMPCONFPATH'}        = $EMPTY;
  local $ENV{'MIBDIRS'}             = $EMPTY;
  local $ENV{'MIBS'}                = $EMPTY;
  local $ENV{'SNMP_PERSISTENT_DIR'} = $home;

  SNMP::initMib();

  my @mibdirs = _build_mibdirs();

  foreach my $d (@mibdirs) {
    next unless -d $d;
    SNMP::addMibDirs($d);
  }

  my $session = SNMP::Session->new(
    UseEnums    => 1,
    RetryNoSuch => 1,
    DestHost    => '127.0.0.1',
    Community   => 'public',
    Version     => 2,

    # Hold simulated data for mock sessions
    Data => {},
  );

  my $mock_session = Test::MockObject::Extends->new($session);

  mock_get($mock_session);
  mock_getnext($mock_session);
  mock_set($mock_session);

  return $mock_session;
}

sub _build_mibdirs {
  my $home = dir($ENV{HOME}, 'netdisco-mibs');
  return map { dir($home, $_)->stringify } @{_get_mibdirs_content($home)};
}

sub _get_mibdirs_content {
  my $home = shift;
  my @list
    = map { s|$home/||; $_ } grep {m/[a-z0-9]/} grep {-d} glob("$home/*");
  return \@list;
}

sub mock_get {
  my $mock_session = shift;

  $mock_session->mock(
    'get',
    sub {
      my $self = shift;
      my $vars = shift;
      my ($leaf, $iid, $oid, $oid_name);
      my $c_data = $self->{Data};

      # From SNMP::Info get will only be passed either an OID or
      # SNMP::Varbind with a fully qualified leaf and potentially
      # a partial
      if (ref($vars) =~ /SNMP::Varbind/x) {
        ($leaf, $iid) = @{$vars};
      }
      else {
        $oid = $vars;
        $oid_name = SNMP::translateObj($oid, 0, 1) || $EMPTY;
        ($leaf, $iid) = $oid_name =~ /^(\S+::\w+)[.]?(\S+)*$/x;
      }

      # This is a lot of indirection, but we need the base OID, it may be
      # passed with a zero for non table leaf
      my $oid_base = SNMP::translateObj($leaf);

      $iid ||= 0;
      my $new_iid = $iid;
      my $val     = $EMPTY;
      my $data    = $c_data->{$leaf} || $c_data->{$oid_base} || {};
      my $count   = scalar keys %{$data} || 0;
      if ($count > 1) {
        my $found = 0;
        foreach my $d_iid (sort keys %{$data}) {
          if ($d_iid eq $iid) {
            $val   = $data->{$d_iid};
            $found = 1;
            next;
          }
          elsif ($found == 1) {
            $new_iid = $d_iid;
            last;
          }
        }
        if ($found && ($new_iid eq $iid)) {
          $leaf = 'unknown';
        }
      }
      else {
        $val  = $data->{$iid};
        $leaf = 'unknown';
      }

      if (ref $vars =~ /SNMP::Varbind/x) {
        $vars->[0] = $leaf;
        $vars->[1] = $new_iid;
        $vars->[2] = $val;
      }
      return (wantarray() ? $vars : $val);
    }
  );
  return;
}

sub mock_getnext {
  my $mock_session = shift;

  $mock_session->mock(
    'getnext',
    sub {
      my $self = shift;
      my $vars = shift;
      my ($leaf, $iid, $oid, $oid_name);
      my $c_data = $self->{Data};

      # From SNMP::Info getnext will only be passed a SNMP::Varbind
      # with a fully qualified leaf and potentially a partial
      ($leaf, $iid) = @{$vars};

      # If we captured data using OIDs printed numerically -On option,
      # we need to convert the leaf to an OID for match
      my $leaf_oid = SNMP::translateObj($leaf, 0, 1) || '';

      unless (defined $iid) {
        $iid = -1;
      }
      my $new_iid = $iid;
      my $val     = $EMPTY;
      my $data    = $c_data->{$leaf} || $c_data->{$leaf_oid};
      my $count   = scalar keys %{$data} || 0;
      if ($count) {
        my $found = 0;
        foreach my $d_iid (sort keys %{$data}) {
          if ($d_iid gt $iid && !$found) {
            $val     = $data->{$d_iid};
            $new_iid = $d_iid;
            $found   = 1;
            next;
          }
          elsif ($found == 1) {
            last;
          }
        }
        if ($found && ($new_iid eq $iid)) {
          $leaf = 'unknown';
        }
      }
      else {
        $val  = $data->{$iid};
        $leaf = 'unknown';
      }

      $vars->[0] = $leaf;
      $vars->[1] = $new_iid;
      $vars->[2] = $val;
      return (wantarray() ? $vars : $val);
    }
  );
  return;
}

# For testing purposes assume sets worked
sub mock_set {
  my $mock_session = shift;

  $mock_session->mock(
    'set',
    sub {
      return 1;
    }
  );
  return;
}

# Utility to load snmpwalk from a file to use for mock sessions
sub load_snmpdata {
  my $test      = shift;
  my $data_file = shift;

  my @lines = read_lines($data_file);

  my $snmp_data = {};
  foreach my $line (@lines) {
    next if !$line;
    next if ($line =~ /^#/);
    if ($line =~ /^(\S+::\w+)[.]?(\S+)*\s=\s(.*)$/x) {
      my ($leaf, $iid, $val) = ($1, $2, $3);
      next if !$leaf;
      $iid ||= 0;
      $val =~ s/\"//g;
      $snmp_data->{$leaf}->{$iid} = $val;
    }
  }
  return $snmp_data;
}

# Returns 1 if the method is defined in the symbol table 0 otherwise, used for
# verification that dynamic methods via AUTOLOAD and can() have been inserted
# into the symbol table
sub symbol_test {
  my $test   = shift;
  my $method = shift;

  my $class   = $test->class;
  my %symbols = ();
  {
    no strict 'refs';    ## no critic (ProhibitNoStrict)
    %symbols = %{$class . '::'};
  }
  return (defined($symbols{$method}) ? 1 : 0);
}

1;
