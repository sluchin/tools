#!/usr/bin/perl -w

use strict;
use warnings;
use File::Basename;
use Encode qw/encode_utf8 decode_utf8/;
use utf8;
use JSON qw/encode_json decode_json/;
use Data::Dumper;

our $VERSION = "0.1";
my $progname = basename($0);

opendir my $dh, "./";

sub read_file {
    my $file = shift;

    open my $in, "<", $file
        or print "open: $!";

    my $json;
    while (defined( my $line = <$in> )) {
        $json .= $line;
    }
    close $in;

    #print decode_utf8($json) . "\n";
    my $hash = decode_json(encode_utf8($json));
    my ($str, $indent) = '';
    for (sort keys %{$hash}) {
        my $value = $hash->{$_};
        $str .= "\n$_ == $value\n";
        $str .= recurse_hash($value, $indent);
    }
    #print Dumper $data;
    print decode_utf8($str) . "\n";
}

sub recurse_hash {
    my ( $value, $indent ) = @_;
    my $ref = ref $value;
    my $str = "";

    if ($ref eq 'ARRAY') {
        my $i = 0;
        my $is_empty = 1;
        my @array = @$value;
        $indent .= "    ";
        foreach my $a (@array) {
            if ( defined $a ) {
                $is_empty = 0;
                $str .= "\n$indent\[$i\] :";
                $str .= recurse_hash($a, $indent);
            }
            $i++;
        }
        $str .= "= {}" if ($is_empty);

    } elsif ($ref eq 'HASH') {
        $indent .= "    ";
        foreach my $k (sort keys %$value) {
            if ( ( ref($value->{$k}) eq 'HASH') || (ref $value->{$k} eq 'ARRAY') ) {
                my $val = $value->{$k};
                $str .= "\n\n$indent$k == ";
                $str .= "$val";
            }
            else {
                $str .= "\n$indent$k == ";
            }
            $str .= recurse_hash($value->{$k}, $indent);
        }
    } elsif ($ref eq '') {
        $str .= "$value";
    }

    return $str;
}

if (@ARGV > 0) {
    my $file = $ARGV[0];
    if (-f $file) {
        #print "$file\n";
        read_file($file);
    }
    else {
        print "$file no exist\n";
    }
}
else {
    foreach my $file (readdir($dh)) {
        next if ($file =~ m/^\.{1,2}$/); # '.'や'..'をスキップ
        #print "$file\n";
        read_file($file);
    }
}
