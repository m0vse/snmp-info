# SNMP::Info::Layer3::ERX
#
# Copyright (c) 2017 Rob Woodward
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

package SNMP::Info::Layer3::ERX;

use strict;
use warnings;
use Exporter;
use SNMP::Info::Layer3;

@SNMP::Info::Layer3::ERX::ISA = qw/
  SNMP::Info::Layer3
  Exporter
/;
@SNMP::Info::Layer3::ERX::EXPORT_OK = qw//;

our ($VERSION, %GLOBALS, %MIBS, %FUNCS, %MUNGE);

$VERSION = '3.74';

%MIBS = (
    %SNMP::Info::Layer3::MIBS
);

%GLOBALS = (
    %SNMP::Info::Layer3::GLOBALS,
);

%FUNCS = (
    %SNMP::Info::Layer3::FUNCS,
);

%MUNGE = (
    %SNMP::Info::Layer3::MUNGE,
);

sub vendor {
  return "juniper";
}

sub model {
  my $ERX = shift;
  my $descr = $ERX->description() || '';
  my $model = undef;

  $model = $1 if ( $descr =~ /Juniper Networks, Inc. (.+) Edge Routing Switch/i );

  return $model;
}

sub os {
  return 'JunOSe';
}

sub os_ver {
  my $ERX = shift;
  my $descr  = $ERX->description();
  my $os_ver = undef;

  if ( defined ($descr) && $descr =~ /Version : \((.+)\) .+:/ ) {
    $os_ver = $1;
  }

  return $os_ver;
}

sub i_ignore {
  my $l3      = shift;
  my $partial = shift;

  my $interfaces = $l3->interfaces($partial) || {};

  my %i_ignore;
  foreach my $if ( keys %$interfaces ) {
    # lo0 etc
    if ( $interfaces->{$if} =~ /\b(inloopback|console)\d*\b/i ) {
      $i_ignore{$if}++;
    }
  }
  return \%i_ignore;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::ERX - SNMP Interface to Juniper ERX Layer 3 routers.

=head1 AUTHORS

Rob Woodward

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you.
 my $ERX = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myrouter',
                          Community   => 'public',
                          Version     => 2
                        )
    or die "Can't connect to DestHost.\n";

 my $class      = $ERX->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Subclass for Juniper ERX switches

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=back

=head2 Required MIBs

=over

=item Inherited Classes' MIBs

See L<SNMP::Info::Layer3> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $ERX->vendor()

Returns 'juniper'.

=item $ERX->os()

Returns 'JunOSe'.

=item $ERX->os_ver()

Returns the software version extracted from C<sysDescr>.

=item $ERX->model()

Returns the hardware model extracted from C<sysDescr>.

=back

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3> for details.

=head1 TABLE ENTRIES

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $ERX->i_ignore()

Returns reference to hash. Increments value of IID if port is to be ignored.

Ignores InLoopback and Console interfaces

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3> for details.

=cut
