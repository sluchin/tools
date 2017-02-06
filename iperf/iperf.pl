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
use Expect;

use constant TRUE  => 1;
use constant FALSE => 0;

our $VERSION = do { my @r = ( q$Revision: 0.01 $ =~ /\d+/g );
    sprintf "%d." . "%02d" x $#r, @r if (@r);
};

my $progname = basename($0);
my $progdir;
my $process = $$;
my $exe     = 'iperf';
my $options = '';
my $jsondir = 'iperf_json_' . $process;
my $csvdir  = 'iperf_csv_' . $process;
my $prompt  = '$';
my $timeout = 10;

BEGIN {
    $progdir = dirname( readlink($0) || $0 );
    push( @INC, catfile( $progdir, 'lib' ) );
}

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
    'user'         => undef,
    'pass'         => undef,
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
    'host|c=s'      => \$opt{'host'},
    'user=s'        => \$opt{'user'},
    'pass=s'        => \$opt{'pass'},
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

sub _login {
    my ( $exp, $pass, $to ) = @_;

    print 'timeout=' . ( defined $to ? $to : 'undef' ), "\n";
    $exp->expect(
        $to,
        [
            qr/\(yes\/no\)\?/ => sub {
                my $self = shift;
                $self->send("yes\n");
                exp_continue;
              }
        ],
        [
            qr/word:/ => sub {
                my $self = shift;
                $self->send( $pass . "\n" );
                exp_continue;
              }
        ],
        [
            qr/Permission denied/ => sub {
                exit;
              }
        ],
        $prompt
    );
}

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
            push( @bps, ( $val / 1024 / 1024 ) . 'm' );
        }
        elsif (( $from->{'unit'} =~ m/k/i )
            && ( $to->{'unit'} =~ m/k/i )
            && ( $space->{'unit'} =~ m/k/i ) )
        {
            push( @bps, ( $val / 1024 ) . 'm' );
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
    my ( $bps, $len, $cmd, $e ) = @_;
    my $sum   = $e->{'sum'};
    my $cpu   = $e->{'cpu_utilization_percent'};
    my @array = ();

    print Dumper $sum if ( $opt{'vorbis'} );

    return (
        $bps,                      $len,
        $sum->{'start'},           $sum->{'end'},
        $sum->{'seconds'},         $sum->{'bytes'},
        $sum->{'bits_per_second'}, $sum->{'jitter_ms'},
        $sum->{'lost_packets'},    $sum->{'packets'},
        $sum->{'lost_percent'},    $cpu->{'host_total'},
        $cpu->{'host_user'},       $cpu->{'host_system'},
        $cpu->{'remote_total'},    $cpu->{'remote_user'},
        $cpu->{'remote_system'},   $cmd
    );
}

sub _parse_json_tcp {
    my ( $bps, $len, $cmd, $e ) = @_;
    my $sum_sent = $e->{'sum_sent'};
    my $sum_recv = $e->{'sum_received'};
    my $cpu      = $e->{'cpu_utilization_percent'};
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
        $sum_recv->{'bits_per_second'}, $cpu->{'host_total'},
        $cpu->{'host_user'},            $cpu->{'host_system'},
        $cpu->{'remote_total'},         $cpu->{'remote_user'},
        $cpu->{'remote_system'},        $cmd
    );
}

sub _json_to_csv_end {
    my ( $bps, $len, $cmd, $e ) = @_;

    my @e = ();
    if ( $opt{'udp'} ) {
        @e = _parse_json_udp( $bps, $len, $cmd, $e );
    }
    else {
        @e = _parse_json_tcp( $bps, $len, $cmd, $e );
    }
    my $csv = '';
    foreach my $value (@e) {
        $csv .= ( $value || '0' ) . ',';
    }
    chop($csv);
    return $csv;
}

sub _csv_to_hash_udp {
    my @d    = @_;
    my %hash = (
        'time'      => $d[0]  || '',
        'server'    => $d[1]  || '',
        'sport'     => $d[2]  || '',
        'client'    => $d[3]  || '',
        'cport'     => $d[4]  || '',
        'unclear1'  => $d[5]  || '',
        'interval'  => $d[6]  || '',
        'transfer'  => $d[7]  || '',
        'bandwidth' => $d[8]  || '',
        'jitter'    => $d[9]  || '',
        'lost'      => $d[10] || '',
        'total'     => $d[11] || '',
        'percent'   => $d[12] || '',
        'unclear2'  => $d[13] || '',
    );

    return %hash;
}

sub _csv_to_hash_tcp {
    my @d    = @_;
    my %hash = (
        'time'      => $d[0] || '',
        'server'    => $d[1] || '',
        'sport'     => $d[2] || '',
        'client'    => $d[3] || '',
        'cport'     => $d[4] || '',
        'unclear1'  => $d[5] || '',
        'interval'  => $d[6] || '',
        'transfer'  => $d[7] || '',
        'bandwidth' => $d[8] || '',
    );

    return %hash;
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

sub iperf3 {
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

    my %cpu     = ();
    my %cpufile = ();
    my %csvfile = ();

    $bpsfile{'file'}  = 'iperf_bps_chart_' . $process . '.csv';
    $lostfile{'file'} = 'iperf_lost_chart_' . $process . '.csv';
    $sbpsfile{'file'} = 'iperf_sbps_chart_' . $process . '.csv';
    $rbpsfile{'file'} = 'iperf_rbps_chart_' . $process . '.csv';
    $cpufile{'file'}  = 'iperf_remote_cpu_chart_' . $process . '.csv';

    if ( $opt{'udp'} ) {
        $csvfile{'file'} = 'iperf_udp_' . $process . '.csv';
        push(
            @{ $csvfile{'data'} },
            'bps,length,start,end,seconds,'
              . 'bytes,bits_per_second,jitter_ms,'
              . 'lost_packets,packets,lost_percent,'
              . 'host_total,host_user,host_system,'
              . 'remote_total,remote_user,remote_system,command'
        );
    }
    else {
        $csvfile{'file'} = 'iperf_tcp_' . $process . '.csv';
        push(
            @{ $csvfile{'data'} },
            'bps,length,start,end,seconds,'
              . 'bytes,bits_per_second,retransmits,'
              . 'start,end,seconds,bytes,bits_per_second,'
              . 'host_total,host_user,host_system,'
              . 'remote_total,remote_user,remote_system,command'
        );
    }

    $csvdir .= $opt{'udp'} ? '_udp' : '_tcp';

    foreach my $bps (@sortbps) {
        print $bps->{'bps'} . "\n" if ( $opt{'debug'} );

        foreach my $len ( sort { $b <=> $a } @{ $opt{'length'} } ) {
            print $len . "\n" if ( $opt{'debug'} );

            my $addopt  = $options;
            my $logfile = catfile( $jsondir,
                    'iperf_'
                  . ( $bps->{'bps'} || '' ) . '_'
                  . $len . '_'
                  . '.json' );
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
                $bps{ $bps->{'bps'} }{$len} =
                  $end->{'sum'}->{'bits_per_second'};
                $lost{ $bps->{'bps'} }{$len} = $end->{'sum'}->{'lost_percent'};
            }
            else {
                $sbps{ $bps->{'bps'} }{$len} =
                  $end->{'sum_sent'}->{'bits_per_second'};
                $rbps{ $bps->{'bps'} }{$len} =
                  $end->{'sum_received'}->{'bits_per_second'};
            }
            $cpu{ $bps->{'bps'} }{$len} =
              $end->{'cpu_utilization_percent'}->{'remote_total'};

            my $csvdata =
              _json_to_csv_end( $bps->{'bps'}, $len, ( $exe . $addopt ), $end );
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

    @{ $cpufile{'data'} } = _chart( \%cpu );
    print "\nremote cpu chart:\n" if ( $opt{'vorbis'} );
    _output( \%cpufile );
}

sub server {
    my ( $bps, $len ) = @_;

    my $cmd = 'iperf -s';
    $cmd .= ' -u'         if ( $opt{'udp'} );
    $cmd .= ' -l ' . $len if ($len);
    $cmd .= ' -y c';

    my $logfile = 'iperf_server_' . $bps . '_' . $len . '_' . $process . '.csv';
    my $exp     = Expect->new();
    $exp->spawn( 'ssh -l ' . $opt{'user'} . ' ' . $opt{'host'} )
      or die 'spawn error ', $!;
    _login( $exp, $opt{'pass'}, $timeout );

    open my $save, '>&', STDOUT    # 保存
      or die 'dup error: stdout: ', $!;
    open my $out, '>', $logfile    # ファイルに出力
      or die 'open error: ' . $logfile . ': ', $!;
    binmode $out, ':unix:encoding(utf8)';
    open STDOUT, '>&', $out        # コピー
      or die 'dup error: ' . $logfile . ': ', $!;

    $exp->send( $cmd . "\n" );
    $exp->expect( $timeout, $prompt );

    $exp->send("exit\n");
    $exp->expect( $timeout, $prompt );

    open my $in, '<', $logfile
      or die 'open error: ' . $logfile . ': ', $!;
    my @content = <$in>;
    close $in;

    close($out);

    # 標準出力を戻す
    open STDOUT, '>&', $save
      or die 'dup error: save: ', $!;

    my $csvdata = pop(@content);
    chop($csvdata);
    print $csvdata . "\n" if ( $opt{'debug'} );
    my @data = split /,/, $csvdata;
    print "@data\n";
}

sub iperf2 {

    $options .= ' -u'                    if ( $opt{'udp'} );
    $options .= ' -t ' . $opt{'time'}    if ( $opt{'time'} );
    $options .= ' -i ' . $opt{'interval'};
    $options .= ' -c ' . $opt{'host'};
    $options .= ' -w ' . $opt{'window'}  if ( defined( $opt{'window'} ) );
    $options .= ' -M ' . $opt{'set-mss'} if ( defined( $opt{'set-mss'} ) );
    $options .= ' -y c';

    my ( %bps,     %lost )     = ();
    my ( %bpsfile, %lostfile ) = ();
    my %csvfile = ();

    $bpsfile{'file'}  = 'iperf_bps_chart_' . $process . '.csv';
    $lostfile{'file'} = 'iperf_lost_chart_' . $process . '.csv';

    if ( $opt{'udp'} ) {
        $csvfile{'file'} = 'iperf_udp_' . $process . '.csv';
        push(
            @{ $csvfile{'data'} },
            'bps,length,time,server,sport,'
              . 'client,cport,,'
              . 'interval,transfer,bandwidth,jitter,'
              . 'lost,total,lost_percent,,command'
        );
    }
    else {
        $csvfile{'file'} = 'iperf_tcp_' . $process . '.csv';
        push(
            @{ $csvfile{'data'} },
            'bps,length,time,server,sport,'
              . 'client,cport,,'
              . 'interval,transfer,bandwidth,,command'
        );
    }

    $jsondir .= $opt{'udp'} ? '_udp' : '_tcp';

    foreach my $bps (@sortbps) {
        print $bps->{'bps'} . "\n" if ( $opt{'debug'} );

        foreach my $len ( sort { $b <=> $a } @{ $opt{'length'} } ) {
            print $len . "\n" if ( $opt{'debug'} );

            my $addopt  = $options;
            my $logfile = catfile( $csvdir,
                    'iperf_'
                  . ( $bps->{'bps'} || '' ) . '_'
                  . $len . '_'
                  . '.csv' );
            $addopt .= ' -b ' . ( $bps->{'bps'} || '' );
            $addopt .= ' -l ' . $len;
            $addopt .= ' --output ' . $logfile;
            mkpath($csvdir) unless ( -d $csvdir );

            print "command line:\n" . $exe . $addopt . "\n";
            open my $save, '>&', STDOUT    # 保存
              or die 'dup error: stdout: ', $!;
            open my $out, '>', $logfile    # ファイルに出力
              or die 'open error: ' . $logfile . ': ', $!;
            binmode $out, ':unix:encoding(utf8)';
            open STDOUT, '>&', $out        # コピー
              or die 'dup error: ' . $logfile . ': ', $!;

            system( $exe . $addopt );

            open my $in, '<', $logfile
              or die 'open error: ' . $logfile . ': ', $!;
            my @content = <$in>;
            close $in;

            close($out);

            # 標準出力を戻す
            open STDOUT, '>&', $save
              or die 'dup error: save: ', $!;

            my $csvdata = pop(@content);
            chop($csvdata);
            print $csvdata . "\n" if ( $opt{'debug'} );
            my @data = split /,/, $csvdata;

            my %csv = ();
            if ( $opt{'udp'} ) {
                %csv                         = _csv_to_hash_udp(@data);
                $bps{ $bps->{'bps'} }{$len}  = $csv{'bandwidth'};
                $lost{ $bps->{'bps'} }{$len} = $csv{'percent'};
            }
            else {
                %csv = _csv_to_hash_tcp(@data);
                $bps{ $bps->{'bps'} }{$len} = $csv{'bandwidth'};
            }
            $csvdata =
                $bps->{'bps'} . ','
              . $len . ','
              . $csvdata . ',' . '"'
              . $exe
              . $addopt . '"';
            push( @{ $csvfile{'data'} }, $csvdata );
            print $csvdata. "\n";
        }
    }

    print "\n" if ( $opt{'vorbis'} );
    print 'csv:' . "\n" if ( $opt{'vorbis'} );
    _output( \%csvfile );

    @{ $bpsfile{'data'} } = _chart( \%bps );
    print "\nbps chart:\n" if ( $opt{'vorbis'} );
    _output( \%bpsfile );

    if ( $opt{'udp'} ) {
        @{ $lostfile{'data'} } = _chart( \%lost );
        print "\nlost packet percent chart:\n" if ( $opt{'vorbis'} );
        _output( \%lostfile );
    }
}

# サーバ
# iperf -s -u -l 1500 -y c > filename.csv
iperf2();

print strftime( "[%Y-%m-%d %H:%M:%S]: end", localtime ), "\n";

exit $stathash{'EX_OK'};

__END__

=pod

=encoding utf-8

=head1 SYNOPSIS

 iperf.pl オプション引数

 Options:
    -f, --file filename
        yaml設定ファイル指定
    -c, --host hostname
        サーバのアドレス設定
    -u, --udp
        UDPの指定
    -b, --bandwidth n[KM]
        帯域幅の設定
    -l, --length n[KM]
        パケット長の設定
    -t, --time n
        時間の設定
    -n, --bytes n[KM]
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
    --from n[MK]
        開始帯域幅(--toと同時指定)
    --to n[MK]
        終了帯域幅(--fromと同時指定)
    --space n[MK]
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
