#!/usr/bin/perl -w
#perl -w
#C:\Perl64\bin\perl -w

##
# @file caltime.pl
#
# 勤務時間を計算する.
#
# @author Tetsuya Higashi
# @version $Id$
#
# 使い方
# caltime.pl ファイル
#
# 入力
# グループ,技術開発部チームM,氏名,東　哲也,,,,,,,,,,,,
# 日,曜,始業時刻,,,遅刻事由,外出,,戻り,,終業時刻,,,早退事由,欠勤事由,備考
# 2013/07/01,月,09:00,修,遅,,,,00:00,修,18:00,修,,,,
# 2013/07/01,月,,,,,,,00:00,修,,,,,,
# 2013/07/02,火,09:00,,,,,,,,18:00,修,,,,
# 2013/07/03,水,09:00,修,,,,,,,19:30,修,,,,
#
# 出力
# 日,曜,始業時刻,終業時刻,通常,残業,深夜,休日,休日+深夜,休憩,合計
# 2013/07/01,月,09.00,18.00,8,0,0,,,1,8
# 2013/07/02,火,09.00,18.00,8,0,0,,,1,8
# 2013/07/03,水,09.00,19.50,8,1,0,,,1.5,9
#

use strict;
use warnings;
use File::Basename;
use Getopt::Long;
use utf8;
use Encode qw/encode decode/;

our $VERSION = do { my @r = ( q$Revision: 0.10 $ =~ /\d+/g ); sprintf "%d." . "%02d" x $#r, @r if (@r) };
my $progname = basename($0);

# プロトタイプ
sub print_version();
sub usage();
sub read_files($);
sub read_file($);
sub conv_hour($);
sub conv_min($);
sub round_time($);
sub add_time($$@);

# ステータス
my %stathash = (
    'EX_OK' => 0, # 正常終了
    'EX_NG' => 1, # 異常終了
);

# デフォルトオプション
my %opt = (
    'dir'      => undef,
    'base'     => 0,
    'verbose'  => 0,
    'help'     => 0,
    'version'  => 0,
);

# オプション引数
Getopt::Long::Configure(
    qw(bundling no_getopt_compat no_auto_abbrev no_ignore_case));
GetOptions(
    'dir|d=s'    => \$opt{'dir'},
    'base|b=i'   => \$opt{'base'},
    'verbose|v'  => \$opt{'verbose'},
    'help|h|?'   => \$opt{'help'},
    'version|V'  => \$opt{'version'},
) or usage();

if ($opt{'help'}) {
    usage();
    exit($stathash{'EX_OK'});
}

if ($opt{'version'}) {
    print_version();
    exit($stathash{'EX_OK'});
}

##
# バージョン情報表示
#
sub print_version()
{
    print "$progname version " . $VERSION . "\n" .
          "  running on Perl version " .
          join(".",
              map { $_||=0; $_*1 } ($] =~ /(\d)\.(\d{3})(\d{3})?/ )) . "\n";
}

##
# ヘルプ表示
#
sub usage()
{
    print << "EOF"
Usage: $progname [options][file]
   -d,  --dir        Calcuration files from directory.
   -b,  --base       Base start time(-1=8:00).
   -v,  --verbose    Output verbose message.
   -h,  --help       Display this help and exit.
   -V,  --version    Output version information and exit.
EOF
}

# セパレータ
my $sep = ",";

# 15分単位で集計
my @unitmin = ( 00, 15, 30, 45 );

# 時を変換(00:00 は 24.00)
my %hconv = ( "00" => "24",
              "01" => "25",
              "02" => "26",
              "03" => "27",
              "04" => "28",
              "05" => "29",
              "06" => "30",
              "07" => "31",
              "08" => "32",
              "09" => "33",
);

# 分を変換(9:15 は 9.25)
my %mconv = ( "00" => "00",
              "15" => "25",
              "30" => "50",
              "45" => "75",
);

# 以下の値が範囲内のときに0.25ずつ加算していくとそれぞれの時間がでる
# 通常時間(9:00〜18：00)
my @commontime = (  9.25,  9.50,  9.75, 10.00, # 09:00〜10:00
                   10.25, 10.50, 10.75, 11.00, # 10:00〜11:00
                   11.25, 11.50, 11.75, 12.00, # 11:00〜12:00
                   12.25, 12.50, 12.75, 13.00, # 12:00～13:00
                   13.25, 13.50, 13.75, 14.00, # 13:00〜14:00
                   14.25, 14.50, 14.75, 15.00, # 14:00〜15:00
                   15.25, 15.50, 15.75, 16.00, # 15:00〜16:00
                   16.25, 16.50, 16.75, 17.00, # 16:00〜17:00
                   17.25, 17.50, 17.75, 18.00, # 17:00〜18:00
);

# 残業時間(18:00〜22:00, 5:00〜8:30)
my @overtime = ( 18.25, 18.50, 18.75, 19.00, # 18:00〜19:00
                 19.25, 19.50, 19.75, 20.00, # 19:00〜20:00
                 20.25, 20.50, 20.75, 21.00, # 20:00〜21:00
                 21.25, 21.50, 21.75, 22.00, # 21:00〜22:00
                 29.25, 29.50, 29.75, 30.00, # 05:00〜06:00
                 30.25, 30.50, 30.75, 31.00, # 06:00〜07:00
                 31.25, 31.50, 31.75, 32.00, # 07:00〜08:00
                 32.25, 32.50, 32.75, 33.00  # 08:00〜09:00
);

# 深夜残業(22:00〜5:00)
my @latetime = ( 22.25, 22.50, 22.75, 23.00, # 22:00〜23:00
                 23.25, 23.50, 23.75, 24.00, # 23:00〜00:00
                 24.25, 24.50, 24.75, 25.00, # 00:00～01:00
                 25.25, 25.50, 25.75, 26.00, # 01:00〜02:00
                 26.25, 26.50, 26.75, 27.00, # 02:00〜03:00
                 27.25, 27.50, 27.75, 28.00, # 03:00〜04:00
                 28.25, 28.50, 28.75, 29.00, # 04:00〜05:00
);

# 休憩時間
my @resttime = ( 12.25, 12.50, 12.75, 13.00, # 12:00～13:00
                 18.75, 19.00,               # 18:30～19:00
                 21.75, 22.00,               # 21:30～22:00
                 24.25, 24.50, 24.75, 25.00, # 00:00～01:00
                 27.75, 28.00,               # 03:30～04:00
                 32.75, 33.00,               # 08:30～09:00
);

my $enc;
my $utf8 = 'UTF-8';
if ($^O eq "MSWin32") {
    $enc = 'Shift_JIS';
}
else {
    $enc = $utf8;
}

my %grouphash;
my @grouplst;
my @namelst;
my @filelst;

##
# ディレクトリ配下のファイルを処理
#
sub read_files($) {
    my $dirs = shift;
    my ($in, $out);
    my $output = "";

    opendir($in, $dirs)
        or die print ": open dir error[$dirs]: $!";

    foreach my $dir (readdir($in)) {
        next if $dir =~ /^\.{1,2}$/;
        next unless $dir =~ /^\d{6}\.csv$/;
        read_file($dir);
    }

    foreach my $gname (@grouplst) {
        open $out, ">$gname.csv"
            or die print ": open file error[$gname.csv]: $!";
        $output = "月,グループ,名前,通常,残業,深夜,休日,休日+,合計\n";
        foreach my $file (@filelst) {
            foreach my $group (@{$grouphash{$file}}) {
                next unless ($gname eq ${$grouphash{$file}}[1]);
                $output .= $group;
                $output .= $sep unless ($group eq ${$grouphash{$file}}[-1]);
            }
            $output .= "\n" if ($gname eq ${$grouphash{$file}}[1]);
        }
        print $out encode($enc, $output);
        close($out);
    }
    closedir($in);
}

##
# ファイルを処理
#
sub read_file($)
{
    my $file = shift;
    my ($in, $out, $output);
    my ($date, $week, $begin, $end, $inf);
    my ($common, $over, $late, $rest);
    my ($common_sum, $over_sum, $late_sum);
    my ($holiday_sum, $holi_late_sum);
    my ($diff, $worktime);
    my ($group, $name, $person);
    my @diff;
    my @work;

    return unless (defined $file);

    open $in, "<$file"
        or die print ": open file error[$file]: $!";

    # 1行目
    my $one = <$in>;
    (undef, $group, undef, $name) = split(/,/, $one);
    $group = "" unless (defined $group);
    $name = "" unless (defined $name);
    $group = decode($utf8, $group);
    $name = decode($utf8, $name);
    $name =~ s/\s+//g; # 空白削除

    # 2行目
    my $two = <$in>;

    # ヘッダ
    $output = "日,曜,始業時刻,終業時刻,通常,残業,深夜,休日,休日+深夜,休憩,合計\n";

    while (defined(my $line = <$in>)) {

        chomp($line);
        next if ($line eq "");
        $line = decode($enc, $line);

        ($date, $week, $begin, $inf, undef,
         undef, undef, undef, undef, undef, $end) = split(/,/, $line);

        next unless ((defined $date) || ($date eq ""));

        # 始業時間
        $begin = conv_hour($begin);
        $begin = conv_min($begin);
        next unless defined $begin;
        $output .= "$date" . $sep;
        $output .= "$week" if ((!defined $week) || ($week ne ""));
        $output .= $sep . "$begin";
        $output .= $sep;

        # 終業時間
        $end = conv_hour($end);
        $end = conv_min($end);
        next unless defined $end;
        $output .= "$end";
        $output .= $sep;

        # 通常時間
        @diff = grep { !{map{$_,1}@resttime }->{$_}}@commontime;
        $common = add_time($begin, $end, @diff);
        if (defined $common) {
            if ((defined $inf) && ($inf eq "出")) {
                $holiday_sum += $common;
            }
            else {
                $common_sum += $common;
                $output .= "$common"
            }
        }
        $output .= $sep;

        # 残業時間
        @diff = grep { !{map{$_,1}@resttime }->{$_}}@overtime;
        $over = add_time($begin, $end, @diff);
        if (defined $over) {
            if ((defined $inf) && ($inf eq "出")) {
                # 休日出勤の場合, 残業は関係ない
                $holiday_sum += $over;
            } else {
                $over_sum += $over;
                $output .= "$over";
            }
        }
        $output .= $sep;

        # 深夜残業
        @diff = grep { !{map{$_,1}@resttime }->{$_}}@latetime;
        $late = add_time($begin, $end, @diff);
        if (defined $late) {
            if ((defined $inf) && ($inf eq "出")) {
                # 休日+深夜
                $holi_late_sum += $late;
            }
            else {
                $late_sum += $late;
                $output .= "$late";
            }
        }
        $output .= $sep;

        # 休日出勤
        if ((defined $inf) && ($inf eq "出")) {
            $common += $over if (defined $over);
            $output .= $common;
        }
        $output .= $sep;

        # 休日出勤+深夜
        if ((defined $inf) && ($inf eq "出")) {
            $output .= $late if (defined $late);
        }
        $output .= $sep;

        # 休憩時間取得
        $rest = add_time($begin, $end, @resttime);
        $output .= "$rest" if (defined $rest);
        $output .= $sep;

        # 勤務時間の計算
        $diff = ($end - $begin) - $rest;
        $output .= $diff . "\n";
        $worktime += $diff;
    } # while
    close $in;

    $common_sum = 0.0 unless (defined $common_sum);
    $over_sum = 0.0 unless (defined $over_sum);
    $late_sum = 0.0 unless (defined $late_sum);
    $holiday_sum = 0.0 unless (defined $holiday_sum);
    $holi_late_sum = 0.0 unless (defined $holi_late_sum);
    $worktime = 0.0 unless (defined $worktime);

    # リスト,ハッシュに保存
    push(@grouplst, $group);
    @grouplst = do { my %h; grep { !$h{$_}++ } @grouplst};
    push(@namelst, $name);
    @namelst = do { my %h; grep { !$h{$_}++ } @namelst};
    push(@filelst, $file);
    my ($month, undef, undef) = fileparse($file, ('.csv'));
    decode($utf8, $month);
    @{$grouphash{$file}} = ($month, $group, $name, $common_sum, $over_sum, $late_sum, $holiday_sum, $holi_late_sum, $worktime);

    foreach my $g (@{$grouphash{$file}}) {
        $output .= $g;
        $output .= $sep unless ($g eq ${$grouphash{$file}}[-1]);
    }
    $output .= "\n";

    printf "%s\n", encode($enc, $output) if ($opt{'verbose'});
    printf "%s %s\n", $month, encode($utf8, $name);
    printf "|%s\t|%4d|\n", encode($enc, "通常"), $common_sum;
    printf "|%s\t|%4d|\n", encode($enc, "残業"), $over_sum;
    printf "|%s\t|%4d|\n", encode($enc, "深夜"), $late_sum;
    printf "|%s\t|%4d|\n", encode($enc, "休日"), $holiday_sum;
    printf "|%s\t|%4d|\n", encode($enc, "休日+"), $holi_late_sum;
    printf "|%s\t|%4d|\n\n", encode($enc, "合計"), $worktime;

    # ファイルに出力
    $person .= $month . "_" . encode($utf8, $group) unless ($group eq "");
    $person .= "_" . encode($utf8, $name) unless ($name eq "");
    $person .= ".csv";
    open $out, ">$person"
        or die print ": open file error[$person]: $!";
    print $out encode($enc, $output);
    close $out;
}

##
# 時刻を変換
#
sub conv_hour($)
{
    my $time = shift;
    my ($h, $m);
    my $result;

    return undef if (!defined $time) || ($time eq "");

    ($h, $m) = split(/:/, $time); # 時分分割
    if (!defined $h || !defined $m) {
        print "format error[$time]\n";
        return undef;
    }
    # 時
    if ($h != (9 + $opt{'base'})) {
        $h = $hconv{$h} if (exists $hconv{$h});
    }
    $result = $h . ":" . $m;

    return $result;
}

##
# 分を変換
#
sub conv_min($)
{
    my $time = shift;
    my ($h, $m);
    my $round;
    my $result;

    return undef if (!defined $time) || ($time eq "");

    ($h, $m) = split(/:/, $time); # 時分分割
    if (!defined $h || !defined $m) {
        print "format error[$time]\n";
        return undef;
    }
    # 分
    $round = round_time($m); # 丸めちゃう

    if (defined $mconv{$round}) {
        $result = $h . "." . $mconv{$round};
    }
    else { # ここにくることはない
        $result = $h . ".00";
    }
    return $result;
}

sub round_time($)
{
    my $time = shift;

    return "00" unless (defined $time);

    for (my $i = 0; $i < @unitmin; $i++) {
        if ($time <= $unitmin[$i]) {
            return "$unitmin[$i]";
        }
    }
    return "00";
}

##
# @timelstが範囲内の場合,時間を加算
#
sub add_time($$@)
{
    my $begin = shift;
    my $end = shift;
    my @timelst = @_;
    my $addtime = 0;

    return undef if (!defined $begin || !defined $end);

    foreach my $time (@timelst) {
        $time += $opt{'base'};
        if ($begin <= ($time - 0.25) && $time <= $end) {
            $addtime += 0.25;
        }
    }
    return $addtime;
}

# 引数チェック
# if ($#ARGV < 0) {
#     print "no argument\n";
#     exit($stathash{'EX_NG'});
#}

if (defined($opt{'dir'})) {
    unless (-d $opt{'dir'}) {
        print "no directory: $opt{'dir'}";
        exit($stathash{'EX_NG'});
    }
    # ディレクトリ配下全てを処理する
    read_files($opt{'dir'});
}
else {
    unless (-f "$ARGV[0]") {
        print "no file: $ARGV[0]";
        exit($stathash{'EX_NG'});
    }
    # ファイル読み込み処理する
    read_file("$ARGV[0]");
}

exit($stathash{'EX_OK'});

__END__
=head1 NAME

caltime.pl - calcuration work time.

=head1 SYNOPSIS

caltime.pl [options][file]

 Options:
   -d,  --dir        Calcuration files from directory.
   -b,  --base       Base start time(-1=8:00, default 0).
   -v,  --verbose    Output verbose message.
   -h,  --help       Display this help and exit.
   -V,  --version    Output version information and exit.

=over 4

=back

=head1 DESCRIPTION

B<This program> calculation work time.

Example:

./caltime.pl -d \\Share\worktime

\\Share\worktime\
 |-name1_dir\
 |        |-201307.csv
 |        |-201308.csv
 |
 |-name2_dir\
          |-201307.csv

=cut
