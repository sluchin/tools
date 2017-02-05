#!/usr/bin/perl -w

use strict;
use warnings;
use utf8;

use File::Basename qw/basename dirname/;
use File::Copy qw/copy/;
use File::Path qw/mkpath rmtree/;
use File::Temp qw/tempfile/;
use Cwd qw/getcwd/;
use Getopt::Long qw/GetOptions Configure/;
use File::Spec qw/path/;
use File::Spec::Functions qw/catfile/;
use Time::HiRes qw/sleep/;
use Encode qw/encode_utf8 decode_utf8 is_utf8/;
use JSON qw/decode_json/;
use Data::Dumper;

use POSIX qw/strftime locale_h/;

#use Expect;
#use Term::UI;
#use Term::ReadLine;

use constant TRUE  => 1;
use constant FALSE => 0;

our $VERSION = do { my @r = ( q$Revision: 0.01 $ =~ /\d+/g );
    sprintf "%d." . "%02d" x $#r, @r if (@r);
};

my $progname = basename($0);
my $progdir;
my $process = $$;
my $exe     = 'iperf3';
my $options = '';

BEGIN {
    $progdir = dirname( readlink($0) || $0 );
    push( @INC, catfile( $progdir, 'lib' ) );
}
my $jsondir = 'iperf_json_' . $process;

use YAML::Tiny;

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

# デフォルトオプション
my %opt = (
    'file'         => '',
    'host'         => 'localhost',
    'udp'          => 0,
    'bandwidth'    => undef,
    'length'       => undef,
    'time'         => 1,
    'bytes'        => 1475,
    'reverse'      => 0,
    'interval'     => 10,
    'affinity'     => undef,
    'window'       => undef,
    'set-mss'      => undef,
    'tos'          => undef,
    'test'         => 0,
    'from'         => undef,
    'to'           => undef,
    'space'        => 10,
    'bps_interval' => 100,
    'gui'          => 0,
    'debug'        => 0,
    'vorbis'       => 0,
    'help'         => 0,
    'version'      => 0,
);

# バージョン情報表示
sub print_version {
    print "$progname version " . $VERSION, "\n";
    print '  running on Perl version '
      . join( ".", map { $_ ||= 0; $_ * 1 } ( $] =~ /(\d)\.(\d{3})(\d{3})?/ ) ),
      "\n";
    exit( $stathash{'EX_OK'} );
}

# ヘルプ表示
sub usage {
    require Pod::Usage;
    import Pod::Usage;
    pod2usage();
}

# オプション引数
Getopt::Long::Configure(
    qw{posix_default no_ignore_case no_auto_abbrev no_getopt_compat gnu_compat}
);
GetOptions(
    'file|f=s'      => \$opt{'file'},
    'host|c'        => \$opt{'host'},
    'udp|u'         => \$opt{'udp'},
    'bandwidth|b=s' => \@{ $opt{'bandwidth'} },
    'length|l=s'    => \@{ $opt{'length'} },
    'time|t=i'      => \$opt{'time'},
    'bytes|n'       => \$opt{'bytes'},
    'reverse|R'     => \$opt{'reverse'},
    'interval|i'    => \$opt{'interval'},
    'affinity|A=s'  => \$opt{'affinity'},
    'window|w=s'    => \$opt{'window'},
    'set-mss|M=s'   => \$opt{'set-mss'},
    'tos|S=s'       => \$opt{'tos'},
    'from=s'        => \$opt{'from'},
    'to=s'          => \$opt{'to'},
    'space=s'       => \$opt{'space'},
    'test'          => \$opt{'test'},
    'gui!'          => \$opt{'gui'},
    'debug|D'       => \$opt{'debug'},
    'vorbis|v'      => \$opt{'vorbis'},
    'help|h|?'      => \$opt{'help'},
    'version|V'     => \$opt{'version'},
  )
  or usage()
  and exit( $stathash{'EX_NG'} );

usage() and exit( $stathash{'EX_OK'} ) if ( $opt{'help'} );
print_version() if ( $opt{'version'} );

my $config      = undef;
my $config_file = '';

sub _decode_utf8 {
    my $s = shift;
    return is_utf8($s) ? decode_utf8($s) : $s;
}

unless ( ( exists( $opt{'bandwidth'} ) && @{ $opt{'bandwidth'} } )
    || ( exists( $opt{'length'} ) && @{ $opt{'length'} } ) )
{
    $config_file =
      $opt{'file'} || catfile( $progdir, '.iperf_default_conf.yml' );
    if ( -f $config_file ) {
        my $data   = YAML::Tiny::LoadFile($config_file);
        my $string = YAML::Tiny::Dump($data);
        $string           = _decode_utf8($string);
        $config           = YAML::Tiny::Load($string);
        $opt{'bandwidth'} = $config->{'bandwidth'};
        $opt{'length'}    = $config->{'length'};
    }
    else {
        usage();
        exit( $stathash{'EX_NG'} );
    }
}

my $signame = undef;
$SIG{'INT'} = sub {
    $signame = shift;
    die 'catch sig_handler!!!: ' . $signame . ': ', $!;
    exit $stathash{'EX_NG'};
};

my @path  = File::Spec->path;
my $exist = FALSE;
foreach my $dir (@path) {
    $exist = TRUE if ( -x catfile( $dir, $exe ) );
}
print "no iperf\n" and exit( $stathash{'EX_NG'} ) unless ($exist);

$opt{'bytes'} = $opt{'length'} if ( $opt{'test'} );

sub _convert_bytes {
    my ($bytes) = @_;
    my $hash = ();

    $hash->{'bps'} = $bytes;
    unless ( $bytes =~ m/\d$/ ) {
        $hash->{'unit'} = substr( $bytes, -1 );
        my $remain = substr( $bytes, 0, -1 );
        if ( $hash->{'unit'} =~ m/m/i ) {
            $hash->{'val'} = $remain * ( 1024 * 1024 );
        }
        elsif ( $hash->{'unit'} =~ m/k/i ) {
            $hash->{'val'} = $remain * 1024;
        }
        else {
            print("unit error\n");
        }
    }
    else {
        $hash->{'val'} = $bytes;
    }
    return $hash;
}

sub _sort_bps {
    my @bpss   = @_;
    my @target = ();
    my @sorted = ();

    foreach my $bps (@bpss) {
        my $hash = _convert_bytes($bps);
        push( @target, $hash );
    }
    @sorted = sort { $b->{'val'} <=> $a->{'val'} } @target;

    return @sorted;
}

sub _bps_from_to {
    my ( $f, $t, $s ) = @_;

    my @bps   = ();
    my $from  = _convert_bytes($f);
    my $to    = _convert_bytes($t);
    my $space = _convert_bytes($s);
    my $tmp   = 0;
    print "from=$from->{'val'}\n"   if ( $opt{'debug'} );
    print "to=$to->{'val'}\n"       if ( $opt{'debug'} );
    print "space=$space->{'val'}\n" if ( $opt{'debug'} );

    if ( $to->{'val'} < $from->{'val'} ) {
        $tmp           = $from->{'val'};
        $from->{'val'} = $to->{'val'};
        $to->{'val'}   = $tmp;
    }
    if ( $space->{'val'} > ( $to->{'val'} - $from->{'val'} ) ) {
        print "no space\n";
        exit( $stathash{'EX_NG'} );
    }

    my $val = $to->{'val'};
    while ( $from->{'val'} <= $val ) {
        if (   ( $from->{'unit'} =~ m/m/i )
            && ( $to->{'unit'} =~ m/m/i )
            && ( $space->{'unit'} =~ m/m/i ) )
        {
            push( @bps, ( $val / 1024 / 1024 ) );
        }
        elsif (( $from->{'unit'} =~ m/m/i )
            && ( $to->{'unit'} =~ m/m/i )
            && ( $space->{'unit'} =~ m/m/i ) )
        {
            push( @bps, ( $val / 1024 ) );
        }
        else {
            push( @bps, $val );
        }

        $val -= $space->{'val'};
    }
    return @bps;
}

if (   defined( $opt{'from'} )
    && defined( $opt{'to'} ) )
{
    @{ $opt{'bandwidth'} } =
      _bps_from_to( $opt{'from'}, $opt{'to'}, $opt{'space'} );
}

my @sortbps = _sort_bps( @{ $opt{'bandwidth'} } );

sub _parse_json_udp {
    my ( $bps, $len, $e ) = @_;
    my $sum   = $e->{'sum'};
    my @array = ();

    print Dumper $sum if ( $opt{'vorbis'} );

    return (
        $bps,                      $len,
        $sum->{'start'},           $sum->{'end'},
        $sum->{'seconds'},         $sum->{'bytes'},
        $sum->{'bits_per_second'}, $sum->{'jitter_ms'},
        $sum->{'lost_packets'},    $sum->{'packets'},
        $sum->{'lost_percent'}
    );
}

sub _parse_json_tcp {
    my ( $bps, $len, $e ) = @_;
    my $sum_sent = $e->{'sum_sent'};
    my $sum_recv = $e->{'sum_received'};
    my @array    = ();

    print Dumper $sum_sent if ( $opt{'vorbis'} );
    print Dumper $sum_recv if ( $opt{'vorbis'} );

    return (
        $bps,                           $len,
        $sum_sent->{'start'},           $sum_sent->{'end'},
        $sum_sent->{'seconds'},         $sum_sent->{'bytes'},
        $sum_sent->{'bits_per_second'}, $sum_sent->{'retransmits'},
        $sum_recv->{'start'},           $sum_recv->{'end'},
        $sum_recv->{'seconds'},         $sum_recv->{'bytes'},
        $sum_recv->{'bits_per_second'}
    );
}

sub _json_to_csv_end {
    my ( $bps, $len, $e ) = @_;

    my @e = ();
    if ( $opt{'udp'} ) {
        @e = _parse_json_udp( $bps, $len, $e );
    }
    else {
        @e = _parse_json_tcp( $bps, $len, $e );
    }
    my $csv = '';
    foreach my $value (@e) {
        $csv .= ( $value || '0' ) . ',';
    }
    chop($csv);
    return $csv;
}

sub _chart {
    my ($args) = @_;
    my $string = '';
    my @lines  = ();
    foreach my $bps (@sortbps) {
        $string .= ',' . ( $bps->{'bps'} || '' );
    }
    push( @lines, $string );
    foreach my $len ( sort { $b <=> $a } @{ $opt{'length'} } ) {
        $string = ( $len || '' ) . ',';
        foreach my $bps (@sortbps) {
            $string .= ( ${$args}{ $bps->{'bps'} }{$len} || '0' ) . ',';
        }
        chop($string);
        push( @lines, $string );
    }
    return @lines;
}

sub _output {
    my ($info) = @_;
    open my $out, '>', ${$info}{'file'}
      or die 'open error: ' . ${$info}{'file'} . ': ', $!;
    foreach my $line ( @{ ${$info}{'data'} } ) {
        print $line . "\n" if ( $opt{'vorbis'} );
        print $out $line . "\n";
    }
    close $out;
}

print strftime( "[%Y-%m-%d %H:%M:%S]: begin", localtime ), "\n";

$options .= ' -u'                     if ( $opt{'udp'} );
$options .= ' -t ' . $opt{'time'}     if ( $opt{'time'} );
$options .= ' -R'                     if ( $opt{'reverse'} );
$options .= ' --json';
$options .= ' -i ' . $opt{'interval'};
$options .= ' -c ' . $opt{'host'};
$options .= ' -A ' . $opt{'affinity'} if ( defined( $opt{'affinity'} ) );
$options .= ' -w ' . $opt{'window'}   if ( defined( $opt{'window'} ) );
$options .= ' -M ' . $opt{'set-mss'}  if ( defined( $opt{'set-mss'} ) );
$options .= ' -S ' . $opt{'tos'}      if ( defined( $opt{'tos'} ) );
$options .= ' --get-server-output';

my ( %bps,     %lost )     = ();
my ( %bpsfile, %lostfile ) = ();

my ( %sbps,     %rbps )     = ();
my ( %sbpsfile, %rbpsfile ) = ();

my %csvfile = ();

$bpsfile{'file'}  = 'iperf_bps_chart_' . $process . '.csv';
$lostfile{'file'} = 'iperf_lost_chart_' . $process . '.csv';
$sbpsfile{'file'} = 'iperf_sbps_chart_' . $process . '.csv';
$rbpsfile{'file'} = 'iperf_rbps_chart_' . $process . '.csv';

if ( $opt{'udp'} ) {
    $csvfile{'file'} = 'iperf_udp' . $process . '.csv';
    push(
        @{ $csvfile{'data'} },
        'bps,length,start,end,seconds,'
          . 'bytes,bits_per_second,jitter_ms,'
          . 'lost_packets,packets,lost_percent'
    );
}
else {
    $csvfile{'file'} = 'iperf_tcp' . $process . '.csv';
    push(
        @{ $csvfile{'data'} },
        'bps,length,start,end,seconds,'
          . 'bytes,bits_per_second,retransmits,'
          . 'start,end,seconds,bytes,bits_per_second'
    );
}

$jsondir .= $opt{'udp'} ? '_udp' : '_tcp';

foreach my $bps (@sortbps) {
    print $bps->{'bps'} . "\n" if ( $opt{'debug'} );

    foreach my $len ( sort { $b <=> $a } @{ $opt{'length'} } ) {
        print $len . "\n" if ( $opt{'debug'} );

        my $addopt  = $options;
        my $logfile = catfile( $jsondir,
            'iperf_' . ( $bps->{'bps'} || '' ) . '_' . $len . '_' . '.json' );
        $addopt .= ' -b ' . ( $bps->{'bps'} || '' );
        $addopt .= ' -l ' . $len;
        $addopt .= ' --logfile ' . $logfile;
        mkpath($jsondir) unless ( -d $jsondir );

        print "command line:\n" . $exe . $addopt . "\n";
        system( $exe . $addopt );

        open my $in, '<', $logfile
          or die 'open error: ' . $logfile . ': ', $!;
        my $content = do { local $/ = undef; <$in> };
        close $in;

        my $json = decode_json($content);
        print Dumper $json if ( $opt{'debug'} );

        my $start     = $json->{'start'};
        my $end       = $json->{'end'};
        my $intervals = $json->{'intervals'};

        if ( $opt{'udp'} ) {
            $bps{ $bps->{'bps'} }{$len}  = $end->{'sum'}->{'bits_per_second'};
            $lost{ $bps->{'bps'} }{$len} = $end->{'sum'}->{'lost_percent'};
        }
        else {
            $sbps{ $bps->{'bps'} }{$len} =
              $end->{'sum_sent'}->{'bits_per_second'};
            $rbps{ $bps->{'bps'} }{$len} =
              $end->{'sum_received'}->{'bits_per_second'};
        }
        my $csvdata = _json_to_csv_end( $bps->{'bps'}, $len, $end );
        push( @{ $csvfile{'data'} }, $csvdata );
        print $csvdata. "\n";
    }
}

print "\n" if ( $opt{'vorbis'} );
print 'csv:' . "\n" if ( $opt{'vorbis'} );
_output( \%csvfile );

if ( $opt{'udp'} ) {
    @{ $bpsfile{'data'} }  = _chart( \%bps );
    @{ $lostfile{'data'} } = _chart( \%lost );
    print "\nbps chart:\n" if ( $opt{'vorbis'} );
    _output( \%bpsfile );
    print "\nlost packet percent chart:\n" if ( $opt{'vorbis'} );
    _output( \%lostfile );
}
else {
    @{ $sbpsfile{'data'} } = _chart( \%sbps );
    @{ $rbpsfile{'data'} } = _chart( \%rbps );
    print "\nsent bps chart:\n" if ( $opt{'vorbis'} );
    _output( \%sbpsfile );
    print "\nrecieved bps chart:\n" if ( $opt{'vorbis'} );
    _output( \%rbpsfile );
}

print strftime( "[%Y-%m-%d %H:%M:%S]: end", localtime ), "\n";

exit $stathash{'EX_OK'};

__END__

=pod

=encoding utf-8

=head1 SYNOPSIS

 iperf.pl オプション引数

 Options:
    -f, --file
        yaml設定ファイル指定
    -c, --host
        サーバのアドレス設定
    -u, --udp
        UDPの指定
    -b, --bandwidth
        帯域幅の設定
    -l, --length
        パケット長の設定
    -t, --time
        時間の設定
    -n, --bytes
        送信バイト数を指定
    -R, --reverse
        クライアントとサーバを逆にする
    -i, --interval
        中間報告を出力する間隔
    -A, --affinity
        CPUアフィニティの設定
    -w, --window
        ウィンドウサイズの設定
    -M, --set-mss
        MTUの設定
    -S, --tos n
        IPタイプオブサービスの設定
    --from
        開始帯域幅
    --to
        終了帯域幅
    --space
        帯域幅の間隔
    --test
        テストモード
    -D, --debug
        デバッグモード
    -v, --vorbis
        詳細な表示
    -h, --help
        ヘルプの表示
    -V, --version
        バージョン情報の表示
=cut
