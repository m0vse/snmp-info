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
use Exporter 'import';
use SNMP::Info;
use SNMP::Info::Layer2;

our @ISA       = qw/SNMP::Info::Layer2 Exporter/;
our @EXPORT_OK = qw//;
our $VERSION   = '0.09';

# ---------------------------------------------------------------------------
# MIB support
# ---------------------------------------------------------------------------
our %MIBS = (
    %SNMP::Info::Layer2::MIBS,
    'CAMBIUM-MIB'        => 'cambiumAPIPAddress',
);

# Raw getter mappings
our %FUNCS = (
    %SNMP::Info::Layer2::FUNCS,

    # Device globals
    'cam_ip'         => 'cambiumAPIPAddress',      # mgmt IP
    'cam_ip_set'     => 'cambiumAPSetIPAddress',   # alt mgmt IP
    'cam_serial'     => 'cambiumAPSerialNum',
    'cam_model'      => 'cambiumAPModel',
    'cam_sw'         => 'cambiumAPSWVersion',
    'cam_ap_mac'     => 'cambiumAPMACAddress',

    # Clients (Nodes)
    'cam_client_mac' => 'cambiumClientMACAddress',
    'cam_client_ip'  => 'cambiumClientIPAddress',

    # WLAN (SSIDs + VLANs)
    'cam_wlan_ssid'  => 'cambiumWlanSsid',
    'cam_wlan_band'  => 'cambiumWlanBand',
    'cam_wlan_vlan'  => 'cambiumWlanVlan',
);

our %GLOBALS = (
    %SNMP::Info::Layer2::GLOBALS,
    vendor    => 'Cambium',
    os_ver    => 'cambiumAPSWVersion',
    model     => 'cambiumAPModel',
    name      => 'sysName',
    contact   => 'sysContact',
    location  => 'sysLocation',
);




# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------
sub vendor { 'Cambium' }
sub os { 'Cambium' }
sub layers { '00000010' }

sub serial {
    my $self = shift;
    my $v = $self->cam_serial();
    return unless defined $v;
    return ref $v eq 'HASH'
      ? (grep { defined $_ && $_ ne '' } values %$v)[0]
      : $v;
}

# ---------------------------------------------------------------------------
# Management IP (and alias/subnet fallbacks for Addresses tab)
# ---------------------------------------------------------------------------
sub ip {
    my $self = shift;
    my $v = $self->cam_ip() // $self->cam_ip_set();
    return unless $v;
    return ref $v eq 'HASH' ? (sort values %$v)[0] : $v;
}

sub ip_index {
    my ($self, $partial) = @_;
    my $ip = $self->ip() or return {};
    my $ifname = $self->interfaces($partial) || {};
    return {} unless %$ifname;

    my $best;
    for my $iid (sort { $a <=> $b } keys %$ifname) {
        my $n = $ifname->{$iid} // '';
        if ($n =~ /^(?:br|eth)/i) { $best = $iid; last; }
    }
    $best //= (sort { $a <=> $b } keys %$ifname)[0];

    return $best ? { $ip => $best } : {};
}


# Optional: also expose newer shapes Netdisco may read in some paths
sub ip_table {
    my ($self, $partial) = @_;
    my $map = $self->ip_index($partial) || {};
    my %by_if;
    while (my ($ip, $ifidx) = each %$map) { $by_if{$ifidx} = $ip }
    return \%by_if;
}

sub ip_netmask {
    my ($self, $partial) = @_;
    my $tbl = $self->ip_table($partial) || {};
    my %out;
    for my $ifidx (keys %$tbl) {
        my $ip = $tbl->{$ifidx} // '';
        my $mask = '255.255.255.0';
        $mask = '255.0.0.0'       if $ip =~ /^10\./;
        $mask = '255.240.0.0'     if $ip =~ /^172\.(1[6-9]|2\d|3[0-1])\./;
        $mask = '255.255.255.0'   if $ip =~ /^192\.168\./;
        $out{$ifidx} = $mask || '255.255.255.255';
    }
    %out = ( (values(%$tbl))[0] ? ((keys(%$tbl))[0] => '255.255.255.255') : () ) unless %out;
    return \%out;
}

sub _octets_to_mac {
  my ($bytes) = @_;
  return unless defined $bytes && length($bytes) == 6;
  my @o = map { sprintf('%02x', ord($_)) } split //, $bytes;
  my $m = join(':', @o);
  return if $m =~ /^(?:00:){5}00$/ || $m =~ /^(?:ff:){5}ff$/i;
  return $m;
}

# ------------- helpers -------------
sub _normalize_mac_text {
  my ($s) = @_;
  return unless defined $s && length $s;

  $s =~ s/^[\s"']+|[\s"']+$//g;

  if ($s =~ /([0-9A-Fa-f]{2}([-:])){5}[0-9A-Fa-f]{2}/) {
    $s =~ s/[^0-9A-Fa-f]/:/g;
    $s =~ s/::+/:/g;
    my $m = lc $s;
    return if $m =~ /^(?:00:){5}00$/ || $m =~ /^(?:ff:){5}ff$/i;
    return $m;
  }

  if ($s =~ /^[0-9A-Fa-f]{12}$/) {
    my @p = ($s =~ /../g);
    my $m = lc join(':', @p);
    return if $m =~ /^(?:00:){5}00$/ || $m =~ /^(?:ff:){5}ff$/i;
    return $m;
  }

  return;
}

sub _try_decode_any_mac_value {
  my ($v) = @_;
  return unless defined $v && length $v;

  # likely OCTETS
  if (length($v) == 6 && $v =~ /[^\x20-\x7e]/) {
    if (my $m = _octets_to_mac($v)) { return $m }
  }

  # printable text
  if ($v =~ /^[\x20-\x7e]+$/) {
    if (my $m1 = _normalize_mac_text($v)) { return $m1 }

    # ASCII hex list "42:43:2d:..." -> text -> normalize
    if ($v =~ /^(?:[0-9A-Fa-f]{2}:){5,}[0-9A-Fa-f]{2}$/) {
      my @hx  = split /:/, $v;
      my $txt = join('', map { chr hex $_ } @hx);
      if (my $m2 = _normalize_mac_text($txt)) { return $m2 }
      (my $justhex = $txt) =~ s/[^0-9A-Fa-f]//g;
      if (my $m3 = _normalize_mac_text($justhex)) { return $m3 }
    }
  }

  return;
}


sub mac {
  my $self = shift;

  my $raw = $self->cam_ap_mac();
  if (defined $raw) {
    for my $idx (keys %$raw) {
      my $norm = _try_decode_any_mac_value($raw->{$idx});
      next unless $norm;
      print ("**** MAC ADDRESS $norm ****");
      return $norm;
    }
  }

  # D) Nothing else worked
  return $self->SUPER::mac();
}

sub i_mac {
  my $self = shift;
  my $raw  = $self->orig_i_mac() || {};
  my %ok;
  for my $if (keys %$raw) {
    if (my $m = _octets_to_mac($raw->{$if})) {
      $ok{$if} = $m;
      next;
    }
    # if device returns printable text instead of OCTETS (rare), accept it
    if (defined $raw->{$if} && $raw->{$if} =~ /^[\x20-\x7e]+$/) {
      if (my $m2 = _try_decode_any_mac_value($raw->{$if})) {
        $ok{$if} = $m2 if $m2;
      }
    }
  }
  return \%ok;
}


# ---------------------------------------------------------------------------
# Nodes (clients)
# ---------------------------------------------------------------------------
sub at_paddr {
    my $self = shift;
    my $macs = $self->cam_client_mac() || {};
    my %out;
    for my $idx (keys %$macs) {
        my $norm = _cambium_norm_mac($macs->{$idx});
        next unless $norm;
        $out{$idx} = $norm;
    }
    return \%out;
}

sub at_netaddr {
    my $self = shift;
    my $ips = $self->cam_client_ip() || {};
    my %out;
    for my $idx (keys %$ips) {
        my $ip = $ips->{$idx} // next;
        next if $ip eq '' || $ip eq '0.0.0.0';
        $out{$idx} = $ip;
    }
    return \%out;
}

# ---------------------------------------------------------------------------
# SSIDs per interface (i_ssidlist)
# ---------------------------------------------------------------------------
sub i_ssidlist {
    my ($self, $partial) = @_;
    my $ssid  = $self->cam_wlan_ssid()  || {};
    my $band  = $self->cam_wlan_band()  || {};
    return {} unless %$ssid;

    my $ifdescr = $self->i_description($partial) || {};

    my (@rad24, @rad5, @bridge);
    for my $iid (keys %$ifdescr) {
        my $n = lc($ifdescr->{$iid} // '');
        push @rad24,  $iid if $n =~ /radio0|wlan0/;
        push @rad5,   $iid if $n =~ /radio1|wlan1|wlan16/;
        push @bridge, $iid if $n =~ /^br/;
    }

    my @rad_any = sort { $a <=> $b }
                  grep { (lc($ifdescr->{$_}||'')) =~ /^(?:radio|wlan)/ }
                  keys %$ifdescr;
    @rad24  = @rad24  ? @rad24  : (@rad_any ? ($rad_any[0]) : ());
    @rad5   = @rad5   ? @rad5   : (@rad_any > 1 ? ($rad_any[1]) : @rad_any);
    @bridge = @bridge ? @bridge : ();

    my %acc;
    for my $idx (keys %$ssid) {
        my $s = $ssid->{$idx};
        next unless defined $s && $s ne '';
        my $b = ($band->{$idx} // 'both');
        my @targets;
        if    ($b =~ /5ghz/i)    { @targets = @rad5; }
        elsif ($b =~ /2\.4ghz/i) { @targets = @rad24; }
        else                     { @targets = (@rad24, @rad5); }
        @targets = @bridge unless @targets;
        for my $iid (@targets) {
            next unless defined $iid;
            push @{ $acc{$iid} }, $s;
        }
    }

    for my $iid (keys %acc) {
        my %seen; $acc{$iid} = [ grep { !$seen{$_}++ } @{ $acc{$iid} } ];
    }
    return \%acc;
}

# ---------------------------------------------------------------------------
# VLANs (from cambiumWlanVlan + brX.<vid> names)
# ---------------------------------------------------------------------------
sub v_index {
    my $self = shift;
    my $vlan = $self->cam_wlan_vlan() || {};
    my %idx;
    for my $k (keys %$vlan) {
        my $vid = $vlan->{$k};
        next unless defined $vid && $vid =~ /^\d+$/;
        $idx{$vid} = $vid;
    }
    return \%idx;
}

sub v_name {
    my $self = shift;
    my $ssid = $self->cam_wlan_ssid() || {};
    my $vlan = $self->cam_wlan_vlan() || {};
    my %map;
    for my $k (keys %$vlan) {
        my $vid = $vlan->{$k};
        next unless defined $vid && $vid =~ /^\d+$/;
        my $name = $ssid->{$k};
        $map{$vid} ||= (defined $name && $name ne '' ? $name : sprintf('VLAN %d',$vid));
    }
    return \%map;
}

sub i_vlan {
    my ($self, $partial) = @_;
    my $ifdescr = $self->i_description($partial) || {};
    my $vlan    = $self->cam_wlan_vlan() || {};
    my %pvid;

    # br*.VID suffix
    for my $iid (keys %$ifdescr) {
        my $n = $ifdescr->{$iid} // next;
        if ($n =~ /\.([0-9]{1,4})$/) {
            $pvid{$iid} = $1 + 0;
        }
    }

    # radios with exactly one WLAN VLAN
    my $targets = _wlan_targets($self, $partial);
    my %by_if;
    for my $idx (keys %$vlan) {
        my $vid = $vlan->{$idx};
        next unless defined $vid && $vid =~ /^\d+$/;
        for my $iid (@{ $targets->{$idx} || [] }) {
            push @{ $by_if{$iid} }, $vid;
        }
    }
    for my $iid (keys %by_if) {
        my %uniq; my @u = grep { !$uniq{$_}++ } @{ $by_if{$iid} };
        $pvid{$iid} = $u[0] if @u == 1 && !exists $pvid{$iid};
    }
    return \%pvid;
}

sub i_vlan_membership {
    my ($self, $partial) = @_;
    my $ifdescr = $self->i_description($partial) || {};
    my $vlan    = $self->cam_wlan_vlan() || {};
    my %m;

    # from br*.VID
    for my $iid (keys %$ifdescr) {
        my $n = $ifdescr->{$iid} // next;
        if ($n =~ /\.([0-9]{1,4})$/) {
            $m{$iid} ||= [];
            push @{ $m{$iid} }, $1 + 0;
        }
    }

    # WLAN VLANs to radio/bridge targets
    my $targets = _wlan_targets($self, $partial);
    for my $idx (keys %$vlan) {
        my $vid = $vlan->{$idx};
        next unless defined $vid && $vid =~ /^\d+$/;
        for my $iid (@{ $targets->{$idx} || [] }) {
            $m{$iid} ||= [];
            push @{ $m{$iid} }, $vid;
        }
    }

    for my $iid (keys %m) {
        my %seen; my @u = sort { $a <=> $b } grep { !$seen{$_}++ } @{ $m{$iid} };
        $m{$iid} = \@u;
    }
    return \%m;
}

sub _wlan_targets {
    my ($self, $partial) = @_;
    my $ifdescr = $self->i_description($partial) || {};
    my $band    = $self->cam_wlan_band() || {};

    my (@rad24, @rad5, @bridge);
    for my $iid (keys %$ifdescr) {
        my $n = lc($ifdescr->{$iid} // '');
        push @rad24,  $iid if $n =~ /radio0|wlan0/;
        push @rad5,   $iid if $n =~ /radio1|wlan1|wlan16/;
        push @bridge, $iid if $n =~ /^br/;
    }
    my @rad_any = sort { $a <=> $b }
                  grep { (lc($ifdescr->{$_}||'')) =~ /^(?:radio|wlan)/ }
                  keys %$ifdescr;
    @rad24 = @rad24 ? @rad24 : (@rad_any ? ($rad_any[0]) : ());
    @rad5  = @rad5  ? @rad5  : (@rad_any > 1 ? ($rad_any[1]) : @rad_any);

    my %map;
    for my $idx (keys %$band) {
        my $b = $band->{$idx} // 'both';
        my @targets;
        if   ($b =~ /5ghz/i)     { @targets = @rad5; }
        elsif($b =~ /2\.4ghz/i)  { @targets = @rad24; }
        else                     { @targets = (@rad24, @rad5); }
        @targets = @bridge unless @targets;
        $map{$idx} = \@targets if @targets;
    }
    return \%map;
}




# ---------------------------------------------------------------------------
# Quiet unsupported probes
# ---------------------------------------------------------------------------
sub has_lldp { 0 } sub hasLLDP { 0 }
sub has_cdp  { 0 } sub hasCDP  { 0 }
sub hasSONMP { 0 } sub hasFDP  { 0 }
sub hasEDP   { 0 } sub hasAMAP { 0 }
sub vtp_d_name { return } sub vtp_d_mode { return }
sub pae_control { return }

# Extra noise-suppression stubs
sub i_duplex            { return {} }
sub i_duplex_admin      { return {} }
sub i_speed_admin       { return {} }
sub agg_ports           { return {} }
sub i_subinterfaces     { return {} }
sub i_vlan_type         { return {} }
sub i_err_disable_cause { return {} }
sub i_faststart_enabled { return {} }




1;

__END__

=head1 NAME

SNMP::Info::Layer2::Cambium - SNMP::Info subclass for Cambium cnPilot APs

=head1 DESCRIPTION

- Addresses: exposes mgmt IP and synthesizes IP-MIB alias view (old_ip_*), so the
  address appears on the Addresses tab even when Cambium omits IP-MIB tables.
- Nodes: populates from cambiumClientMACAddress/IP with MAC normalisation.
- SSIDs: i_ssidlist from cambiumWlanSsid/Band.
- VLANs: v_index/v_name from cambiumWlanVlan; PVID + membership based on WLAN mapping
  and interface names like br0.100.
- Suppresses unsupported feature probes (LLDP/CDP/VTP/PAE/etc.).

=head1 AUTHOR

Phil-friendly edition ;-)

=cut
