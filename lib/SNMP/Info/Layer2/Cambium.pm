# SNMP::Info::Layer2::Cambium - SNMP Interface to Cambium Devices
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


@SNMP::Info::Layer2::Cambium::ISA = qw/SNMP::Info::Layer2 Exporter/;
@SNMP::Info::Layer2::Cambium::EXPORT_OK = qw//;

our ($VERSION, %FUNCS, %GLOBALS, %MIBS, %MUNGE);

$VERSION = '3.970001';

%MIBS = (
    %SNMP::Info::Layer2::MIBS,
    'CAMBIUM-MIB'        => 'cambiumAPSerialNum',
);

%GLOBALS = (
    %SNMP::Info::Layer2::GLOBALS,
    # CAMBIUM-MIB::cambiumAccessPointTable
);

%FUNCS = (
    %SNMP::Info::Layer2::FUNCS,


    # CAMBIUM-MIB::cambiumAccessPointTable
    'cam_serial' 	=> 'cambiumAPSerialNum',
    'cam_os_ver' 	=> 'cambiumAPSWVersion',
    'cam_name'      	=> 'cambiumAPName',
    'cam_ip'        	=> 'cambiumAPIPAddress',
    'cam_type'      	=> 'cambiumAPHWTpe',
    'cam_ip_index'   	=> 'cambiumAPIPAddress',
    'cam_mac'   	=> 'cambiumAPMACAddress',
    'ip_addresses'   	=> 'cambiumAPIPAddress',

    # CAMBIUM-MIB::cambiumRadioTable
    'cam_r_index'     	=> 'cambiumRadioIndex',
    'cam_r_channel'     => 'cambiumRadioChannel',
    'cam_r_power'      	=> 'cambiumRadioTransmitPower',
    'cam_r_bandtype'    => 'cambiumRadioBandType',
    'cam_r_radiostate'  => 'cambiumRadioState',

    # CAMBIUM-MIB::cambiumWlanTable
    'cam_w_index' => 'cambiumWlanIndex',
    'cam_w_vlan' => 'cambiumWlanVlan',
    'cam_w_band' => 'cambiumWlanBand',
    'cam_w_ssid' => 'cambiumWlanSsid',
    'cam_v_index' => 'cambiumWlanVlan',
    'cam_v_name' => 'cambiumWlanSsid',


    # CAMBIUM-MIB::cambiumClientTable
    'cd11_index'     => 'cambiumClientMACAddressIndex',
    'cd11_uptime'     => 'cambiumClientMACAddressIndex',
    'cd11_txrate'      => 'cambiumClientTxRate',
    'cd11_rateset'     => 'cambiumClientTxRate',
    'cd11_sigstrength' => 'cambiumClientSNR',
    'cd11_sigqual' => 'cambiumClientSNR',
    'cd11_rxpkt'       => 'cambiumClientTotalRxPackets',
    'cd11_txpkt'       => 'cambiumClientTotalTxPackets',
    'cd11_rxbyte'      => 'cambiumClientRxDataBytes',
    'cd11_txbyte'      => 'cambiumClientTxDataBytes',
    'cd11_ssid'        => 'cambiumClientSsid',
    'cam_cd11_port'    => 'cambiumClientRadioIndex',
    'cd11_mac'         => 'cambiumClientMACAddress',
    'cd11_mode'        => 'cambiumClientHwMode',
    'fw_vlan'          => 'cambiumClientVlan',
    'cam_c_ip'         => 'cambiumClientIPAddress',
);

%MUNGE = ( 
    %SNMP::Info::Layer2::MUNGE, 
    'cd11_txrate'   => \&munge_cd11_txrate,
    'cd11_rateset'  => \&munge_cd11_txrate,
    'cd11_mac' => \&munge_cam_mac,
);

sub munge_cd11_txrate {
    my $txrates = shift;
    my @units   = unpack( "C*", $txrates );
    my @rates   = map {
        my $unit = $_;
        $unit = int($unit);
    } @units;

    return \@rates;
}

sub munge_cam_mac {
    my $mac = shift;
    return unless defined $mac;
    $mac =~ tr/-/:/;
    return $mac;
}


sub layers {
    return '00000111';
}

sub os {
	return 'cambium';
}

sub vendor {
    return 'cambium';
}

# These should "always" be a hash with a single value, so return the first found value.
# We could use the system OIDs instead I guess, but this uses the 'proper' Cambium MIB.
sub serial {
    my $cambium = shift;
    my @vals;
    my $vals = $cambium->cam_serial();
    return  (values %$vals)[0];
}

sub os_ver {
    my $cambium = shift;
    my @vals;
    my $vals = $cambium->cam_os_ver();
    return  (values %$vals)[0];
}

sub name {
    my $cambium = shift;
    my @vals;
    my $vals = $cambium->cam_name();
    return  (values %$vals)[0];
}

sub ip {
    my $cambium = shift;
    my @vals;
    my $vals = $cambium->cam_ip();
    return  (values %$vals)[0];
}

sub type {
    my $cambium = shift;
    my @vals;
    my $vals = $cambium->cam_type();
    return  (values %$vals)[0];
}

sub mac {
    my $cambium = shift;
    my @vals;
    my $vals = $cambium->cam_mac();
    return  (values %$vals)[0];
}



sub interfaces {
    my $cambium = shift;
    my $partial = shift;

    my $ports = $cambium->orig_interfaces($partial) || {};
    my $names = $cambium->i_description($partial) || {};

    my %interfaces = ();
    foreach my $iid ( keys %$ports ) {
        my $port = $ports->{$iid}; 
        my $name = $names->{$iid}; 
        next unless defined $port;
        next if $name =~ /(lo|bond|sit|soc|port-channel|br|gre|ip6|miireg)/i;
        $interfaces{$iid} = $name;
    }
    return \%interfaces;
}


# Does not support the standard Bridge MIB
sub bp_index {
    my $cambium = shift;
    my $partial  = shift;

    # somewhere caching is doing something strange, without load_
    # netdisco can't find bp_index mappings & will not registerer
    # any clients. netdisco/netdisco#496
    my $interfaces = $cambium->interfaces($partial) || {};

    my %bp_index;
    foreach my $iid ( keys %$interfaces ) {
        my $index = $interfaces->{$iid};
        #print "Adding bp_index mapping: $index=$iid";
        next unless defined $index;

        $bp_index{$index} = $iid;
    }

    return \%bp_index;
}

sub i_type {
    my $cambium = shift;
    my $partial = shift;

    my $interfaces = $cambium->interfaces($partial) || {};
    my $i_desc = $cambium->i_description($partial) || {};
    my $orig_i_type = $cambium->orig_i_type($partial) || {};

    my %i_type = ();
    foreach my $iid ( keys %$interfaces ) {
        my $type = $orig_i_type->{$iid};
        my $desc = $i_desc->{$iid};
        next unless defined $desc;
 	if ($desc =~ /wlan/i) {
            $type = 'capwapWtpVirtualRadio';
        }
        $i_type{$iid} = $type;
    }
    return \%i_type;
}


sub i_name {
    my $cambium = shift;
    my $partial = shift;

    my $interfaces = $cambium->interfaces($partial) || {};
    my $i_desc = $cambium->i_description($partial) || {};
    my $w_ssid = $cambium->cam_w_ssid($partial) || {};
    my $w_band = $cambium->cam_w_band($partial) || {};
    my $r_bandtype = $cambium->cam_r_bandtype($partial) || {};

    my %i_name = ();
    foreach my $iid ( sort keys %$interfaces ) {
        my $desc = $i_desc->{$iid};
 	if ($desc =~ /wlan/i) {
            $desc =~ s/[^0-9]//g; #Strip everything but numbers
            my $ssidname = $w_ssid->{$desc};
      	    if (!defined $ssidname) {
                $ssidname = $w_ssid->{$desc-16};
            }
      	    if (!defined $ssidname) {
                $ssidname = $w_ssid->{$desc-32};
            }
            next unless defined $ssidname;
    	    $i_name{$iid} = $ssidname;
        } elsif ($desc =~ /radio|wifi/i) {
            $desc =~ s/[^0-9]//g; #Strip everything but numbers
            my $bandname = $r_bandtype->{$desc};
            next unless defined $bandname;
    	    $i_name{$iid} = $bandname;
	} else {
            $i_name{$iid} = $desc;
        }
    }
    return \%i_name;
}

sub i_vlan {
    my $cambium = shift;
    my $partial = shift;

    my $interfaces = $cambium->interfaces($partial) || {};
    my $i_desc = $cambium->i_description($partial) || {};
    my $w_ssid = $cambium->cam_w_ssid($partial) || {};
    my $w_vlan = $cambium->cam_w_vlan($partial) || {};
    my $w_band = $cambium->cam_w_band($partial) || {};
    my $r_bandtype = $cambium->cam_r_bandtype($partial) || {};

    my %i_name = ();
    foreach my $iid ( sort keys %$interfaces ) {
        my $desc = $i_desc->{$iid};
 	if ($desc =~ /wlan/i) {
            $desc =~ s/[^0-9]//g; #Strip everything but numbers
      	    my $vlan = $w_vlan->{$desc};
      	    if (!defined $vlan) {
                $vlan = $w_vlan->{$desc-16};
            }
      	    if (!defined $vlan) {
                $vlan = $w_vlan->{$desc-32};
            }
            next unless defined $vlan;
    	    $i_name{$iid} = $vlan;
        } else {
            $i_name{$iid} = '1';
        }
    }
    return \%i_name;
}

sub ip_index {
    my $cambium = shift;
    my $partial = shift;

    my $interfaces = $cambium->interfaces($partial) || {};
    my $ip_index = $cambium->cam_ip_index($partial) || {};

    my %ip_index;
    foreach my $iid ( keys %$interfaces ) {
        my $index = $interfaces->{$iid};
        foreach my $iid2 ( keys %$ip_index) {
            my $ipindex = $ip_index->{iip2};
            next unless $index eq 'eth0';
            $ip_index{$iid2} = $iid;
        }
    }

    return \%ip_index;
}


sub fw_mac {
    my $cambium = shift;
    my $partial = shift;
    my $cd11_mac = $cambium->cd11_mac($partial) || {};
    my %fw_mac = ();
    foreach my $iid (keys %$cd11_mac) {
        my $mac = $cd11_mac->{$iid};
        next unless defined $mac;
    	$fw_mac{$iid} = $mac;
    }
    return \%fw_mac;    
}

sub fw_port {
    my $cambium = shift;
    my $partial = shift;
    my $cd11_mac = $cambium->cd11_mac($partial) || {};
    my $cd11_port = $cambium->cd11_port($partial) || {};
    my %fw_port = ();
    foreach my $iid (keys %$cd11_port) {
        my $mac = $cd11_mac->{$iid};
        next unless defined $mac;
        my $port = $cd11_port->{$iid};
    	$fw_port{$iid} = $port;
    }
    return \%fw_port;    
}


sub i_ssidlist {
    my $cambium = shift;
    my $partial = shift;

    my $interfaces = $cambium->interfaces($partial) || {};
    my $i_desc = $cambium->i_description($partial) || {};
    my $w_ssid = $cambium->cam_w_ssid($partial) || {};

    my %i_ssid = ();
    foreach my $iid ( sort keys %$interfaces ) {
        my $desc = $i_desc->{$iid};
 	if ($desc =~ /wlan/i) {
            $desc =~ s/[^0-9]//g; #Strip everything but numbers
            my $ssidname = $w_ssid->{$desc};
      	    if (!defined $ssidname) {
                $ssidname = $w_ssid->{$desc-16};
            }
      	    if (!defined $ssidname) {
                $ssidname = $w_ssid->{$desc-32};
            }
            next unless defined $ssidname;
    	    $i_ssid{$iid} = $ssidname;
        } 
    }
    return \%i_ssid;
}


sub i_ssidmac {
    my $cambium = shift;
    my $partial = shift;

    my $interfaces = $cambium->interfaces($partial) || {};
    my $i_desc = $cambium->i_description($partial) || {};
    my $i_macs = $cambium->i_mac($partial) || {};

    my %i_mac = ();
    foreach my $iid ( sort keys %$interfaces ) {
        my $desc = $i_desc->{$iid};
 	if ($desc =~ /wlan/i) {
	    my $mac = $i_macs->{$iid};
    	    $i_mac{$iid} = $mac;
        } 
    }
    return \%i_mac;
}


# Doesn't appear to be available on the Cambium MIB?
sub i_ssidbcast {
    my $cambium = shift;
    my $partial = shift;

    my $interfaces = $cambium->interfaces($partial) || {};
    my $i_desc = $cambium->i_description($partial) || {};

    my %i_bcast = ();
    foreach my $iid ( sort keys %$interfaces ) {
        my $desc = $i_desc->{$iid};
 	if ($desc =~ /wlan/i) {
    	    $i_bcast{$iid} = "true";
        } 
    }
    return \%i_bcast;
}


sub dot11_cur_tx_pwr_mw {
    my $cambium = shift;
    my $partial = shift;

    my $interfaces = $cambium->interfaces($partial) || {};
    my $i_desc = $cambium->i_description($partial) || {};
    my $w_ssid = $cambium->cam_w_ssid($partial) || {};
    my $w_band = $cambium->cam_w_band($partial) || {};
    my $r_bandtype = $cambium->cam_r_bandtype($partial) || {};
    my $r_power = $cambium->cam_r_power($partial) || {};

    my %i_name = ();
    foreach my $iid ( sort keys %$interfaces ) {
        my $radio = 0;
        my $desc = $i_desc->{$iid};
 	if ($desc =~ /wlan/i) {
            $desc =~ s/[^0-9]//g; #Strip everything but numbers
            my $type = $w_band->{$desc};
      	    if (!defined $type) {
                $type = $w_band->{$desc-16};
                $radio++;
            }
      	    if (!defined $type) {
                $type = $w_band->{$desc-32};
                $radio++;
            }
            next unless defined $type;
	    # band will now contain either 2.4Ghz, 5Ghz, 6Ghz, (or both/all)
            foreach my $iid2 (keys %$r_bandtype) {
                my $power = $r_power->{$iid2};              
                if ($r_bandtype->{$iid2} eq $type) {
    	            $i_name{$iid} = $power;
                } elsif ('both' eq $type or 'all' eq $type) {
                    if ($radio == $iid2) {
       	                $i_name{$iid} = $power;
		    }
                }
            }

        } 
    }
    return \%i_name;
}

sub i_80211channel {
    my $cambium = shift;
    my $partial = shift;

    my $interfaces = $cambium->interfaces($partial) || {};
    my $i_desc = $cambium->i_description($partial) || {};
    my $w_ssid = $cambium->cam_w_ssid($partial) || {};
    my $w_band = $cambium->cam_w_band($partial) || {};
    my $r_bandtype = $cambium->cam_r_bandtype($partial) || {};
    my $r_channel = $cambium->cam_r_channel($partial) || {};

    my %i_name = ();
    foreach my $iid ( sort keys %$interfaces ) {
        my $radio = 0;
        my $desc = $i_desc->{$iid};
 	if ($desc =~ /wlan/i) {
            $desc =~ s/[^0-9]//g; #Strip everything but numbers
            my $type = $w_band->{$desc};
      	    if (!defined $type) {
                $radio++;
                $type = $w_band->{$desc-16};
            }
      	    if (!defined $type) {
                $radio++;
                $type = $w_band->{$desc-32};
            }
            next unless defined $type;
	    # band will now contain either 2.4Ghz, 5Ghz, 6Ghz, (or both/all)
            foreach my $iid2 (keys %$r_bandtype) {
                my $chan = $r_channel->{$iid2};              
                if ($r_bandtype->{$iid2} eq $type) {
    	            $i_name{$iid} = $chan;
                } elsif ('both' eq $type or 'all' eq $type) {
                    if ($radio == $iid2) {
       	                $i_name{$iid} = $chan;
		    }
                }
            }

        } 
    }
    return \%i_name;
}

sub cd11_port {
    my $cambium = shift;
    my $partial = shift;

    my $cd11_mac = $cambium->cd11_mac($partial) || {};
    my $cd11_port = $cambium->cam_cd11_port($partial) || {};
    my $cd11_ssid = $cambium->cd11_ssid($partial) || {};
    my $i_name = $cambium->i_name($partial) || {};
    my $i_desc = $cambium->i_description($partial) || {};
    my $interfaces = $cambium->interfaces($partial) || {};
    my $i_mac = $cambium->i_mac($partial) || {};
    my $w_band = $cambium->cam_w_band($partial) || {};
    my $r_bandtype = $cambium->cam_r_bandtype($partial) || {};
    my $r_channel = $cambium->cam_r_channel($partial) || {};

    my %ports = ();
    foreach my $iid ( keys %$cd11_port ) {
        my $port;

        #my $radionum=$cd11_port->{$iid}-1;
        my $ssid=$cd11_ssid->{$iid};
        
        foreach my $id ( keys %$interfaces ) {
            my $cid = $i_name->{$id};
            my $ifid = $i_desc->{$id};
            if ($ssid eq $cid) {
                print "Got ssid: $ssid ifid: $ifid\n";
                #$port = $i_mac->{$id};
                $port = $interfaces->{$id};                
                last;
            } 
        }
        next unless defined $port;
       	$ports{$iid} = $port;
    }
    return \%ports;
}

sub at_paddr {
    my $cambium = shift;
    my $ips = $cambium->cam_c_ip() || {};
    my $mac = $cambium->cd11_mac() || {};

    my $ret = {};
    foreach my $idx ( keys %$ips ) {
        next if ( $ips->{$idx} eq '0.0.0.0' );
        $ret->{$idx} = $mac->{$idx};
    }
    return $ret;
}

sub at_netaddr {
    my $cambium = shift;
    my $ips = $cambium->cam_c_ip() || {};

    my $ret = {};
    foreach my $idx ( keys %$ips ) {
        next if ( $ips->{$idx} eq '0.0.0.0' );
        $ret->{$idx} = $ips->{$idx};
    }
    return $ret;
}


1;
__END__

=head1 NAME

SNMP::Info::Layer2::Cambium - SNMP Interface to Cambium Access Points

=head1 AUTHOR

Phil Taylor M0VSE

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you.
 my $cambium = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        )
    or die "Can't connect to DestHost.\n";

 my $class = $cambium->class();
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
