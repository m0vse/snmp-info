# SNMP::Info::Layer2::Ubiquiti - SNMP Interface to Ubiquiti Devices
#
# Copyright (c) 2024 Phil Taylor M0VSE
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

package SNMP::Info::Layer2::Cambium;

use strict;
use warnings;
use Exporter;
use SNMP::Info::Layer2;



@SNMP::Info::Layer2::Cambium::ISA       = qw/SNMP::Info::Layer2 Exporter/;
@SNMP::Info::Layer2::Cambium::EXPORT_OK = qw//;

our ($VERSION, %FUNCS, %GLOBALS, %MIBS, %MUNGE);

$VERSION = '1.000000';

%MIBS = (
    %SNMP::Info::Layer2::MIBS,
    'CAMBIUM-MIB'        => 'cambiumAPSerialNum',
);

%GLOBALS = (
    %SNMP::Info::Layer2::GLOBALS,

    # CAMBIUM-MIB
    'cambium_serial'  => 'cambiumAPSerialNum',
    'cambium_version' => 'cambiumAPSWVersion',
    'cambium_model'   => 'cambiumAPModel',
    'cambium_mac'     => 'cambiumAPMACAddress',
);

%FUNCS = (
    %SNMP::Info::Layer2::FUNCS,

    # CAMBIUM-MIB::cambiumRadioTable
    'i_80211channel'      => 'cambiumRadioChannel',
    'dot11_cur_tx_pwr_mw' => 'cambiumRadioTransmitPower',

    # CAMBIUM-MIB::cambiumWlanTable
    'cambium_i_ssidlist' => 'cambiumWlanIndex',
    'cambium_i_name'     => 'cambiumWlanSsid',

    # CAMBIUM-MIB::cambiumClientTable
    'cd11_txrate'      => 'cambiumClientTxRate',
    'cd11_sigstrength' => 'cambiumClientSNR',
    'cd11_rxpkt'       => 'cambiumClientTotalRxPackets',
    'cd11_txpkt'       => 'cambiumClientTotalTxPackets',
    'cd11_rxbyte'      => 'cambiumClientRxDataBytes',
    'cd11_txbyte'      => 'cambiumClientTxDataBytes',
    'cd11_ssid'        => 'cambiumClientSsid',
    'cambium_c_vlan'   => 'cambiumClientVlan',
    'cambium_c_ip'     => 'cambiumClientIPAddress',
);

%MUNGE = ( %SNMP::Info::Layer2::MUNGE);

sub os {
	return 'CambiumOS';
}

sub os_ver {
    my $cambium = shift;

    my $versions = $cambium->cambium_version();

    foreach my $iid ( keys %$versions ) {
        my $ver = $versions->{$iid};
        next unless defined $ver;
        return $ver;

    }
}

sub vendor {
    return 'cambium';
}

sub model {
    my $cambium = shift;

    my $names = $cambium->cambium_model();

    foreach my $iid ( keys %$names ) {
        my $prod = $names->{$iid};
        next unless defined $prod;
        return $prod;
    }
}

## simply take the MAC and clean it up
sub serial {
    my $cambium = shift;

    my $snum = $cambium->cambium_serial();
    
	foreach my $iid ( keys %$snum ) {
        my $ser = $snum->{$iid};
        next unless defined $ser;
        return $ser;
    }
    return ;
}

sub mac {
	
	my $cambium = shift;

    my $addresses = $cambium->cambium_mac();
    
	foreach my $iid ( keys %$addresses ) {
        my $macaddr = $addresses->{$iid};
        next unless defined $macaddr;
        return $macaddr;
    }
    return ;
}


1;
__END__

=head1 NAME

SNMP::Info::Layer2::Cambium - SNMP Interface to Cambium Access Points

=head1 AUTHOR

Phil Taylor M0VSE

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you.
 my $ubnt = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        )
    or die "Can't connect to DestHost.\n";

 my $class = $ubnt->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from
Cambium Access Point through SNMP.

=head2 Inherited Classes

=over

=item SNMP::Info::Layer2

=back

=head2 Required MIBs

None.

=head2 Inherited MIBs

See L<SNMP::Info::Layer2/"Required MIBs"> for its MIB requirements.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $cambium->vendor()

Returns 'cambium'

=item $cambium->model()

Returns the model extracted from cambiumAPModel

=item $cambium->serial()

Serial Number.

=item $cambium->mac()

Bridge MAC address.

=item $cambium->os()

Returns CambiumOS

=item $cambium->os_ver()

Returns the software version extracted from cambiumAPSWVersion

=back

=head2 Global Methods imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::IEEE802dot11

See L<SNMP::Info::IEEE802dot11/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $cambium->interfaces()

Uses the i_name() field.

=item $cambium->i_ignore()

Ignores interfaces with "CPU Interface" in them.

=back

=head2 Table Methods imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"TABLE METHODS"> for details.

=cut
