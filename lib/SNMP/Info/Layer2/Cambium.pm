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



# --- ssidlist ----------------------------------------------------

# ===================== Cambium SSID & client mapping ======================

# Tell Netdisco which ifIndexes are wireless. This enables Wireless worker to store rows.
sub i_wireless {
  my ($i) = @_;
  my $names = $i->i_name || {};
  my %w;
  while (my ($if, $nm) = each %$names) {
    next unless defined $nm;
    # Treat WLAN interfaces as wireless; include radioN if you want channel/power on radios too.
    if ($nm =~ /^wlan\d+$/i || $nm =~ /^radio\d+$/i) {
      $w{$if} = 1;
    }
  }
  return \%w;
}



# --- SSID broadcast flag per ifIndex (1=broadcast)
sub i_ssidbcast {
  my ($i) = @_;

  my $ssid_by_if = $i->i_ssidlist() || {};  # ifIndex -> SSID (you said this is OK)
  my %out;

  # Mark every SSID-bearing interface as broadcast (1).
  for my $if (keys %$ssid_by_if) {
    $out{$if} = 1;
  }
  return \%out;
}

# --- BSSID per ifIndex (MAC). Use per-interface MAC from IF-MIB.
sub i_ssidmac {
  my ($i) = @_;

  my $i_name     = $i->i_name() || {};      # ifIndex -> name
  my $i_mac      = $i->i_mac()  || {};      # ifIndex -> MAC (binary/hex munged by SNMP::Info)
  my $ssid_by_if = $i->i_ssidlist() || {};  # only return for ports that actually host an SSID

  my %out;
  while (my ($if, $nm) = each %$i_name) {
    next unless defined $nm && $nm =~ /^wlan\d+$/i;
    next unless exists $ssid_by_if->{$if};         # only for SSID-bearing ifIndexes
    my $mac = $i_mac->{$if};
    next unless defined $mac && $mac ne '';
    $out{$if} = $mac;                               # SNMP::Info will munge to xx:xx:.. form
  }
  return \%out;
}

# --- helpers ---------------------------------------------------------------

# Normalize Cambium band strings to 'both' / '2.4' / '5'
sub _cb_norm_band {
  my ($s) = @_;
  return '' unless defined $s;
  $s = lc $s;
  return 'both' if $s =~ /both/;
  return '2.4'  if $s =~ /2\.?4/;
  return '5'    if $s =~ /\b5g?/;
  return '';
}

# Build: name maps, radio list, wlan buckets by radioNum, etc.
# Returns:
#  - \%ifname    : ifIndex -> ifName
#  - \%name2idx  : ifName  -> ifIndex
#  - \@rad_nums  : [ 0, 1, ... ] radios present
#  - \%wlan_by_r : radioNum -> [ ifIndex, ... ] (ordered)
sub _cb_collect_ifaces {
  my ($i) = @_;
  my $names = $i->i_name || {};

  my (%ifname, %name2idx);
  while (my ($idx, $nm) = each %$names) {
    next unless defined $nm && $nm ne '';
    $ifname{$idx}  = $nm;
    $name2idx{$nm} = $idx;
  }

  # radios present (radio0, radio1, ...)
  my @rad_nums;
  for my $idx (keys %ifname) {
    my $nm = $ifname{$idx};
    if (defined $nm && $nm =~ /^radio(\d+)$/i) {
      push @rad_nums, $1 + 0;
    }
  }
  @rad_nums = sort { $a <=> $b } @rad_nums;

  # Bucket wlanX by radio using Cambium's 16-per-radio convention.
  my %wlan_by_r = map { $_ => [] } @rad_nums;
  for my $idx (sort { $a <=> $b } keys %ifname) {
    my $nm = $ifname{$idx} // next;
    next unless $nm =~ /^wlan(\d+)$/i;
    my $wnum   = $1 + 0;
    my $rnum   = int($wnum / 16); # wlan0-15 -> radio0, 16-31 -> radio1, etc.
    # Only bucket if that radio actually exists
    push @{ $wlan_by_r{$rnum} }, $idx if grep { $_ == $rnum } @rad_nums;
  }

  return (\%ifname, \%name2idx, \@rad_nums, \%wlan_by_r);
}

# --- SSIDs to ports --------------------------------------------------------

# Map *all configured* WLAN profiles to concrete ports:
# - 'both' => one wlanX from *each* radio bucket
# - '2.4'  => one from radio whose band is 2.4
# - '5'    => one from radio whose band is 5
# Fallbacks are safe and never throw; if a bucket is empty we just skip that leg.
sub i_ssidlist {
  my ($i) = @_;

  my ($ifname, $name2idx, $rad_nums, $wlan_by_r) = _cb_collect_ifaces($i);
  return {} unless @$rad_nums;

  my $ssid_tbl = $i->cambiumWlanSsid || {};   # wlanProfileIdx -> SSID
  my $band_tbl = $i->cambiumWlanBand || {};   # wlanProfileIdx -> string band

  # Per radio, what band is it? (Cambium says per radio)
  my $rb        = $i->cambiumRadioBandType || {}; # idx -> '2.4GHz'/'5GHz'
  my %radio_band;
  for my $k (keys %$rb) {
    my ($n) = ($k =~ /(\d+)$/);
    $radio_band{$n+0} = _cb_norm_band($rb->{$k});
  }

  # Process WLAN profiles in ascending numeric order
  my @profiles = sort { ($a =~ /(\d+)$/ ? $1 : 0) <=> ($b =~ /(\d+)$/ ? $1 : 0) } keys %$ssid_tbl;

  my %if_to_ssid;

  PROFILE:
  for my $k (@profiles) {
    my ($pidx) = ($k =~ /(\d+)$/);
    next unless defined $pidx;

    my $ssid = $ssid_tbl->{$k};
    next unless defined $ssid && $ssid ne '';

    my $wb = _cb_norm_band( $band_tbl->{$k} // '' );

    if ($wb eq 'both') {
      # Take one wlan from every radio bucket
      for my $r (@$rad_nums) {
        my $ary = $wlan_by_r->{$r} || [];
        my $ifx = shift @$ary;              # may be undef if bucket empty
        $wlan_by_r->{$r} = $ary;            # write back mutation
        $if_to_ssid{$ifx} = $ssid if defined $ifx;
      }
      next PROFILE;
    }

    # Single-band SSID: find a radio that matches this band and take one wlan from its bucket
    if ($wb eq '2.4' || $wb eq '5') {
      for my $r (@$rad_nums) {
        next unless ($radio_band{$r} || '') eq $wb;
        my $ary = $wlan_by_r->{$r} || [];
        my $ifx = shift @$ary;
        $wlan_by_r->{$r} = $ary;
        if (defined $ifx) {
          $if_to_ssid{$ifx} = $ssid;
          next PROFILE;
        }
      }
      # No matching radio had capacity; fall through to best-effort
    }

    # Best-effort fallback: first bucket with capacity
    for my $r (@$rad_nums) {
      my $ary = $wlan_by_r->{$r} || [];
      my $ifx = shift @$ary;
      $wlan_by_r->{$r} = $ary;
      if (defined $ifx) {
        $if_to_ssid{$ifx} = $ssid;
        last;
      }
    }
  }

  # Strip any undef keys (safety) and return hashref
  delete $if_to_ssid{undef};
  return \%if_to_ssid;
}

# --- Client counts per interface ------------------------------------------
# Use cambiumClientWlan (profile idx) + cambiumClientRadioIndex (1-based)
# to put clients on the exact wlanX chosen above.
sub i_ssidmembers {
  my ($i) = @_;

  my ($ifname, $name2idx, $rad_nums, $wlan_by_r_seed) = _cb_collect_ifaces($i);
  return {} unless @$rad_nums;

  # Rebuild the same i_ssidlist allocation so we know (profile, radio) -> ifIndex
  my $ssid_tbl = $i->cambiumWlanSsid || {};
  my $band_tbl = $i->cambiumWlanBand || {};
  my $rb       = $i->cambiumRadioBandType || {};

  my %radio_band;
  for my $k (keys %$rb) {
    my ($n) = ($k =~ /(\d+)$/);
    $radio_band{$n+0} = _cb_norm_band($rb->{$k});
  }

  # Clone wlan buckets so we can pop from them independently
  my %wlan_by_r = map { my $r=$_; $r => [ @{ $wlan_by_r_seed->{$r} // [] } ] } keys %$wlan_by_r_seed;

  my @profiles = sort { ($a =~ /(\d+)$/ ? $1 : 0) <=> ($b =~ /(\d+)$/ ? $1 : 0) } keys %$ssid_tbl;
  my %slot_for;  # $slot_for{$profile_idx}{$radioNum} = ifIndex

  for my $k (@profiles) {
    my ($pidx) = ($k =~ /(\d+)$/);
    next unless defined $pidx;
    my $wb = _cb_norm_band( $band_tbl->{$k} // '' );

    if ($wb eq 'both') {
      for my $r (@$rad_nums) {
        my $ifx = shift @{ $wlan_by_r{$r} || [] } // next;
        $slot_for{$pidx}{$r} = $ifx;
      }
      next;
    }

    if ($wb eq '2.4' || $wb eq '5') {
      for my $r (@$rad_nums) {
        next unless ($radio_band{$r} || '') eq $wb;
        my $ifx = shift @{ $wlan_by_r{$r} || [] } // next;
        $slot_for{$pidx}{$r} = $ifx;
        last;
      }
      next;
    }

    # Fallback
    for my $r (@$rad_nums) {
      my $ifx = shift @{ $wlan_by_r{$r} || [] } // next;
      $slot_for{$pidx}{$r} = $ifx;
      last;
    }
  }

  # Now count clients
  my $cli_wlan  = $i->cambiumClientWlan       || {}; # idx -> profile number
  my $cli_radio = $i->cambiumClientRadioIndex || {}; # idx -> 1..N (1-based)

  my %cnt;
  for my $k (keys %$cli_wlan) {
    my $pidx = $cli_wlan->{$k};
    next unless defined $pidx && $pidx =~ /^\d+$/;

    my $r1 = $cli_radio->{$k};
    next unless defined $r1 && $r1 =~ /^\d+$/;

    my $pos = $r1 - 1;                      # 1-based to 0-based
    next if $pos < 0 || $pos > $#$rad_nums;
    my $rnum = $rad_nums->[$pos];

    my $ifx = $slot_for{$pidx}{$rnum} // next;
    $cnt{$ifx}++;
  }

  return \%cnt;
}


# --- Radio channel: map Cambium radio index -> ifIndex(radioY)
sub i_80211channel {
  my $i     = shift;
  my $names = $i->i_name || {};
  my %radio_if;
  for my $ifIndex (keys %$names) {
    my $n = $names->{$ifIndex} // next;
    $radio_if{$1} = $ifIndex if $n =~ /^radio(\d+)$/i;
  }

  my $chan_tbl = $i->cambiumRadioChannel || {};
  my %out;

  for my $k (keys %$chan_tbl) {
    my ($r_idx) = ($k =~ /(\d+)$/);
    next unless defined $r_idx;
    my $ifIndex = $radio_if{$r_idx};
    next unless defined $ifIndex;
    my $val = $chan_tbl->{$k};
    next unless defined $val && $val ne '';
    $out{$ifIndex} = $val + 0; # stringify digits -> numeric
  }
  return \%out;
}

# --- Radio TX power (Cambium dBm integer -> mW as Netdisco expects)
sub dot11_cur_tx_pwr_mw {
  my $i     = shift;
  my $names = $i->i_name || {};
  my %radio_if;
  for my $ifIndex (keys %$names) {
    my $n = $names->{$ifIndex} // next;
    $radio_if{$1} = $ifIndex if $n =~ /^radio(\d+)$/i;
  }

  my $pwr_tbl = $i->cambiumRadioTransmitPower || {};
  my %out;

  for my $k (keys %$pwr_tbl) {
    my ($r_idx) = ($k =~ /(\d+)$/);
    next unless defined $r_idx;
    my $ifIndex = $radio_if{$r_idx};
    next unless defined $ifIndex;
    my $dbm = $pwr_tbl->{$k};
    next unless defined $dbm && $dbm =~ /^-?\d+(?:\.\d+)?$/;
    my $mw = (10 ** ($dbm / 10));
    $out{$ifIndex} = int($mw + 0.5);
  }
  return \%out;
}


# --- map WLAN index -> ifIndex(wlanX)
sub _wlan_idx_to_ifindex {
  my ($i) = @_;
  my $names = $i->i_name() || {};
  my %wlan_if;
  while (my ($if, $nm) = each %$names) {
    next unless defined $nm && $nm =~ /^wlan(\d+)$/i;
    $wlan_if{$1} = $if;
  }
  return \%wlan_if; # { wlanIdx => ifIndex }
}

# ============================================================
# cd11_* API expected by Netdisco's Wireless worker
# ============================================================

# cd11_mac: { ifIndex => [ mac, ... ] }  (primary list used by worker)
sub cd11_mac {
  my ($i) = @_;
  my $wlan_map = _wlan_idx_to_ifindex($i);              # wlanIdx -> ifIndex
  my $mac_tbl  = $i->cambiumClientMACAddress() || {};   # idx -> STRING
  my $wlan_tbl = $i->cambiumClientWlan()      || {};    # idx -> INTEGER wlanIdx

  my %by_if;
  for my $k (keys %$mac_tbl) {
    my ($idx) = ($k =~ /(\d+)$/) or next;
    my $widx = $wlan_tbl->{$k};
    next unless defined $widx;
    my $if   = $wlan_map->{$widx} // next;

    my $mac  = _try_decode_any_mac_value($mac_tbl->{$k}) // next;
    push @{ $by_if{$if} }, $mac;
  }
  return \%by_if;
}

# cd11_ip: { mac => ip }   (optional enrichment)
sub cd11_ip {
  my ($i) = @_;
  my $mac_tbl = $i->cambiumClientMACAddress() || {};
  my $ip_tbl  = $i->cambiumClientIPAddress()  || {};
  my %mac2ip;

  for my $k (keys %$mac_tbl) {
    my $mac = _cam_str_to_mac($mac_tbl->{$k}) // next;
    my $ip  = $ip_tbl->{$k};
    next unless defined $ip && $ip =~ /^\d{1,3}(?:\.\d{1,3}){3}$/;
    $mac2ip{$mac} = $ip;
  }
  return \%mac2ip;
}

# cd11_port: { mac => ifIndex }  (lets worker bind client to port directly)
sub cd11_port {
  my ($i) = @_;
  my $wlan_map = _wlan_idx_to_ifindex($i);
  my $mac_tbl  = $i->cambiumClientMACAddress() || {};
  my $wlan_tbl = $i->cambiumClientWlan()      || {};
  my %mac2if;

  for my $k (keys %$mac_tbl) {
    my $mac  = _try_decode_any_mac_value($mac_tbl->{$k}) // next;
    my $widx = $wlan_tbl->{$k};
    my $if   = defined $widx ? $wlan_map->{$widx} : undef;
    next unless defined $if;
    $mac2if{$mac} = $if;
  }
  return \%mac2if;
}

# cd11_ssid: { mac => ssid } (optional, nice for UI)
sub cd11_ssid {
  my ($i) = @_;
  my $mac_tbl  = $i->cambiumClientMACAddress() || {};
  my $wlan_tbl = $i->cambiumClientWlan()      || {};
  my $ssid_tbl = $i->cambiumWlanSsid()        || {};
  my %mac2ssid;

  for my $k (keys %$mac_tbl) {
    my $mac  = _try_decode_any_mac_value($mac_tbl->{$k}) // next;
    my $widx = $wlan_tbl->{$k};
    my $ssid = defined $widx ? $ssid_tbl->{$widx} : undef;
    next unless defined $ssid && $ssid ne '';
    $mac2ssid{$mac} = $ssid;
  }
  return \%mac2ssid;
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
