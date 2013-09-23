#!/usr/bin/perl -w
# COPYRIGHT:
#
# Copyright (c) 2013 Tetsuya Higashi
# All rights reserved.
#
# LICENSE:
#
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.

use strict;
use warnings;
use File::Basename qw/basename dirname fileparse/;
use Getopt::Long;
use utf8;
use Encode qw/encode decode/;

our $VERSION = do { my @r = ( q$Revision: 0.16 $ =~ /\d+/g );
    sprintf "%d." . "%02d" x $#r, @r if (@r);
};

my $progname = basename($0);
my $progdir;

BEGIN {
    $progdir = dirname( readlink($0) || $0 );
    push( @INC, $progdir . '/lib' );
}
use Caltime;

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);


# バージョン情報表示
sub print_version {
    print "$progname version "
      . $VERSION . "\n"
      . "  running on Perl version "
      . join( ".", map { $_ ||= 0; $_ * 1 } ( $] =~ /(\d)\.(\d{3})(\d{3})?/ ) )
      . "\n";
    exit( $stathash{'EX_OK'} );
}


# ヘルプ表示
sub usage {
    require Pod::Usage;
    import Pod::Usage;
    pod2usage();
}

# デフォルトオプション
my %opt = (
    'dir'     => undef,
    'offset'  => 0,
    'group'   => 0,
    'weekly'  => 0,
    'verbose' => 0,
    'help'    => 0,
    'version' => 0,
);

# オプション引数
Getopt::Long::Configure(
    qw(bundling no_getopt_compat no_auto_abbrev no_ignore_case));
GetOptions(
    'dir|d=s'    => \$opt{'dir'},
    'offset|o=i' => \$opt{'offset'},
    'group|g'    => \$opt{'group'},
    'weekly|w'   => \$opt{'weekly'},
    'verbose|v'  => \$opt{'verbose'},
    'help|h|?'   => \$opt{'help'},
    'version|V'  => \$opt{'version'},
  )
  or usage()
  and exit( $stathash{'EX_NG'} );

usage() and exit( $stathash{'EX_OK'} ) if ( $opt{'help'} );
print_version() if ( $opt{'version'} );

# セパレータ
our $sep = ",";

# 9:00から出勤
our $basetime = 9.00;

# エンコード
my ( $enc, $dec );
if ( $^O eq "MSWin32" ) {
    $enc = 'Shift_JIS';
    $dec = 'Shift_JIS';
}
elsif ( $^O eq "cygwin" ) {
    $enc = 'UTF-8';
    $dec = 'Shift_JIS';
}
else {
    $enc = 'UTF-8';
    $dec = 'Shift_JIS';
}

my %grouphash;
my %namehash;
my @grouplst;
my @namelst;
my @filelst;
my @datelst;

# 初期化
sub init {
    $common_sum = $over_sum = $late_sum = $holiday_sum = 0.0;
    $holi_late_sum = $worktime = 0.0;
    @datelst = ();
}

# 週単位の合計文字列
sub sum_weekly {
    return
        $datelst[0] . "-"
      . $datelst[-1]
      . $sep
      . $common_sum
      . $sep
      . $over_sum
      . $sep
      . $late_sum
      . $sep
      . $holiday_sum
      . $sep
      . $holi_late_sum
      . $sep
      . $worktime . "\n";
}


# 結果の表示
sub print_result {
    my ( $name, $date ) = @_;

    $date = $datelst[0] . "-" . $datelst[-1] unless ( defined $date );
    printf "%s %s\n", $date, encode( $enc, $name );
    printf "|%s\t|%6.2f|\n",   encode( $enc, "通常" ),  $common_sum;
    printf "|%s\t|%6.2f|\n",   encode( $enc, "残業" ),  $over_sum;
    printf "|%s\t|%6.2f|\n",   encode( $enc, "深夜" ),  $late_sum;
    printf "|%s\t|%6.2f|\n",   encode( $enc, "休日" ),  $holiday_sum;
    printf "|%s\t|%6.2f|\n",   encode( $enc, "休日+" ), $holi_late_sum;
    printf "|%s\t|%6.2f|\n\n", encode( $enc, "合計" ),  $worktime;
}

# ディレクトリ配下のファイルを処理
sub read_files {
    my $basedir = shift;
    my $output;
    my $filename;

    my @dirs = recursive_dir($basedir);
    return unless (@dirs);
    foreach my $dir ( sort @dirs ) {
        print $dir . "\n";
        read_file($dir);
    }

    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime(time);
    my $datetime = sprintf(
        "%04d%02d%02d%02d%02d%02d",
        $year + 1900,
        $mon + 1, $mday, $hour, $min, $sec
    );

    # グループごとの集計
    if ( $opt{'group'} ) {
        foreach my $gname (@grouplst) {
            $filename = $datetime . "_" . encode( $enc, $gname ) . ".csv";
            open my $out, ">", $filename
              or die "open[$filename]: $!";
            $output =
"月,グループ,名前,通常,残業,深夜,休日,休日+深夜,合計\n";
            foreach my $file (@filelst) {
                foreach my $group ( @{ $grouphash{$file} } ) {
                    next unless ( $gname eq ${ $grouphash{$file} }[1] );
                    $output .= $group;
                    $output .= $sep
                      unless ( $group eq ${ $grouphash{$file} }[-1] );
                }
                $output .= "\n" if ( $gname eq ${ $grouphash{$file} }[1] );
            }
            print $out encode( $enc, $output );
            close($out);
        }
    }

    # 名前ごとの週単位集計
    if ( $opt{'weekly'} || !$opt{'group'} ) {
        foreach my $name (@namelst) {
            my $interval = "";
            my $bmon     = "";
            $filename = $datetime . "_" . encode( $enc, $name ) . ".csv";
            open my $out, ">", $filename
              or die "open[$filename]: $!";
            $common_sum = $over_sum = $late_sum = $holiday_sum = 0.0;
            $holi_late_sum = $worktime = 0.0;
            $output =
              "日,通常,残業,深夜,休日,休日+深夜,休憩,合計\n";
            foreach my $n ( @{ $namehash{$name} } ) {
                my ( $date, $week, $begin, $end, $inf ) = split /,/, $n;
                my ( undef, $month, undef ) = split /\//, $date;
                if ( ( $month = $month || "" ) eq "" ) {
                    printf "format error[%s]\n", $month;
                }

                # 連続していない月は, 一旦出力する
                if (   $bmon ne ""
                    && $month ne ""
                    && !( ( $month + 0 ) <= ( $bmon + 1 ) ) )
                {
                    $output .= sum_weekly();
                    print_result($name);
                    init();
                }

                push( @datelst, $date );
                calc_sum( $begin, $end, $opt{'offset'}, $inf eq '出' ? 1 : 0 );

                if ( $week eq '日' ) {
                    $output .= sum_weekly();
                    print_result($name);
                    init();
                }
                $bmon = $month;
            }

            if (@datelst) {
                $output .= sum_weekly();
                print_result($name);
            }
            printf "%s\n", encode( $enc, $output ) if ( $opt{'verbose'} );

            print $out encode( $enc, $output );
            close($out);
        }
    }
}


# ファイルを処理
sub read_file {
    my $file = shift;
    my ( $in, $out, $output );
    my ( $date, $week, $begin, $end, $inf, $comment );
    my ( $common, $over, $late, $offset );
    my ( $group, $name, $person, $sum, $debug );
    my @diff;
    my @work;

    return unless ( defined $file );
    return unless basename($file) =~ /\d{6}\.csv$/;

    open $in, "<", "$file"
      or die "open[$file]: $!";

    # 1行目
    my $one = <$in>;
    ( undef, $group, undef, $name ) = split( /,/, $one );
    $group = "" unless ( defined $group );
    $name  = "" unless ( defined $name );
    $group = decode( $dec, $group );
    $name  = decode( $dec, $name );
    $name =~ s/\s+//g;    # 空白削除

    # 2行目
    my $two = <$in>;

    # ヘッダ
    $output =
"日,曜,始業時刻,終業時刻,通常,残業,深夜,休日,休日+深夜,休憩,合計\n";

    # 出勤時間
    init();
    while ( defined( my $line = <$in> ) ) {

        $offset = $opt{'offset'} % 24;
        chomp($line);
        next if ( $line eq "" );
        $line = decode( $dec, $line );

        (
            $date, $week, $begin, $inf,  undef, $comment,
            undef, undef, undef,  undef, $end
        ) = split( /,/, $line );

        next unless ( ( defined $date ) || ( $date eq "" ) );
        $output .= $date;
        $output .= $sep;
        $output .= $week if ( ( !defined $week ) || ( $week ne "" ) );
        $output .= $sep;
        $debug .= $date . $sep if ( $opt{'verbose'} );

        # 始業時刻のコメントの先頭に時刻フォーマットの文字列がある場合
        if ( defined $comment ) {   # 時刻からオフセット値を求める
            if ( $comment =~ /^\d{2}:\d{2}/ ) {
                $comment = substr( $comment, 0, 5 );
                $comment = conv_min($comment);
                print "$comment\n" if ( $opt{'verbose'} );
                if ( $basetime < $comment ) {
                    $offset = $comment - $basetime;
                }
            }
        }

        # 始業時間
        $begin = conv_hour( $begin, $offset )
          if ( 15 <= $offset );    # 00:00以上
        $begin = conv_min( $begin, $offset );
        if ( defined $begin ) {
            $debug .= sprintf( "%2.2f", $begin ) . $sep if ( $opt{'verbose'} );
            $output .= val2str($begin);
        }
        $output .= $sep;

        # 終業時間
        $end = conv_hour( $end, $offset );
        $end = conv_min( $end, $offset );
        if ( defined $end ) {
            $debug .= sprintf( "%2.2f", $end ) . $sep if ( $opt{'verbose'} );
            $output .= val2str($end);
        }
        $output .= $sep;
        $sum = calc_sum( $begin, $end, $offset, $inf eq '出' ? 1 : 0 );
        $output .= $sum;
        $debug  .= $sum if ( $opt{'verbose'} );
        $begin  .= "";
        $end    .= "";
        my $regist =
          $date . $sep . $week . $sep . $begin . $sep . $end . $sep . $inf;
        push( @{ $namehash{$name} }, $regist );

    }    # while
    close $in;

    # リスト,ハッシュに保存
    push( @grouplst, $group );
    @grouplst = do {
        my %h;
        grep { !$h{$_}++ } @grouplst;
    };
    push( @namelst, $name );
    @namelst = do {
        my %h;
        grep { !$h{$_}++ } @namelst;
    };
    push( @filelst, $file );
    my ( $month, undef, undef ) = fileparse( $file, ('.csv') );
    $month = decode( $dec, $month );
    @{ $grouphash{$file} } = (
        $month,       $group,         $name,
        $common_sum,  $over_sum,      $late_sum,
        $holiday_sum, $holi_late_sum, $worktime
    );

    print $debug . "\n" if ( $opt{'verbose'} );
    printf "%s\n", encode( $enc, $output ) if ( $opt{'verbose'} );
    print_result( $name, $month );

    # ファイルに出力
    $person .= $month;
    $person .= "_" . $group unless ( $group eq "" );
    $person .= "_" . $name unless ( $name eq "" );
    $person .= ".csv";
    $person = encode( $enc, $person );
    open $out, ">", "$person"
      or die "open[$person]: $!";
    print $out encode( $enc, $output );
    close $out;
    init();
}

print "@INC\n" if ( $opt{'verbose'} );

if ( defined( $opt{'dir'} ) ) {
    $opt{'dirs'} = decode( $dec, $opt{'dirs'} );
    unless ( -d $opt{'dir'} ) {
        print "no directory: $opt{'dir'}\n";
        exit( $stathash{'EX_NG'} );
    }

    # ディレクトリ配下全てを処理する
    read_files( $opt{'dir'} );
}
else {

    # 引数チェック
    if ( $#ARGV < 0 ) {
        print "no argument\n";
        exit( $stathash{'EX_NG'} );
    }

    unless ( -f "$ARGV[0]" ) {
        print "no file: $ARGV[0]\n";
        exit( $stathash{'EX_NG'} );
    }

    # ファイル読み込み処理する
    read_file("$ARGV[0]");
}

exit( $stathash{'EX_OK'} );

__END__

=encoding utf-8

=head1 NAME

caltime.pl - calculation work time.

=head1 SYNOPSIS

caltime.pl [options] [-d directory|file]

 Options:
   -d, --dir=directory    Calcuration files from directory.
   -o, --offset           Offset start time(-1=8:00).
   -g, --group            Calcuration for group.
   -w, --weekly           Calcuration weekly.
   -v, --verbose          Display extra information.
   -h, --help             Display this help and exit.
   -V, --version          Output version information and exit.

=over 4

=back

=head1 DESCRIPTION

B<This program> calculation work time.

=head1 EXAMPLE

./caltime.pl -d \\192.168.1.2\share\worktime\ -g

\\192.168.1.2\share\worktime\
 |-name1\
 |    |-201307.csv
 |    |-201308.csv
 |
 |-name2\
      |-201307.csv

=cut
