#!/usr/bin/perl -w
#perl -w
#C:\Perl64\bin\perl -w

##
# 勤務時間を計算する.
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
# ディレクトリ配下
# find . -type f | while read fn; do caltime.pl $fn; done
#

use strict;
use warnings;
use File::Basename;

use utf8;
use Encode qw/encode decode/;

our $VERSION = do { my @r = ( q$Revision: 0.10 $ =~ /\d+/g ); sprintf "%d." . "%02d" x $#r, @r if (@r) };
my $progname = basename($0);

# ステータス
my %stathash = (
    'EX_OK' => 0, # 正常終了
    'EX_NG' => 1, # 異常終了
);

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
my @commontime = (  9.25,  9.50,  9.75, 10.00, #  9:00〜10:00
                   10.25, 10.50, 10.75, 11.00, # 10:00〜11:00
                   11.25, 11.50, 11.75, 12.00, # 11:00〜12:00
                   13.25, 13.50, 13.75, 14.00, # 13:00〜14:00
                   14.25, 14.50, 14.75, 15.00, # 14:00〜15:00
                   15.25, 15.50, 15.75, 16.00, # 15:00〜16:00
                   16.25, 16.50, 16.75, 17.00, # 16:00〜17:00
                   17.25, 17.50, 17.75, 18.00, # 17:00〜18:00
);

# 残業時間(18:00〜22:00, 5:00〜8:30)
my @overtime = ( 18.25, 18.50,               # 18:00〜18:30
                 19.25, 19.50, 19.75, 20.00, # 19:00〜20:00
                 20.25, 20.50, 20.75, 21.00, # 20:00〜21:00
                 21.25, 21.50,               # 21:00〜21:30
                 29.25, 29.50, 29.75, 30.00, # 05:00〜06:00
                 30.25, 30.50, 30.75, 31.00, # 06:00〜07:00
                 31.25, 31.50, 31.75, 32.00, # 07:00〜08:00
                 32.25, 32.50,               # 08:00〜08:30
);

# 深夜残業(22:00〜5:00)
my @latetime = ( 22.25, 22.50, 22.75, 23.00, # 22:00〜23:00
                 23.25, 23.50, 23.75, 24.00, # 23:00〜00:00
                 25.25, 25.50, 25.75, 26.00, # 01:00〜02:00
                 26.25, 26.50, 26.75, 27.00, # 02:00〜03:00
                 27.25, 27.50,               # 03:00〜03:30
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

my $header = "日,曜,始業時刻,終業時刻,通常,残業,深夜,休日,休日+深夜,休憩,合計\n";

my $enc;
my $utf8 = 'UTF-8';
if ($^O eq "MSWin32") {
    $enc = 'Shift_JIS';
}
else {
    $enc = $utf8;
}

sub read_file($)
{
    my $file = shift;
    my ($in, $out, $output);
    my ($date, $week, $begin, $end, $inf);
    my ($common, $over, $late, $rest);
    my ($common_sum, $over_sum, $late_sum);
    my ($holiday_sum, $holi_late_sum);
    my ($diff, $worktime);
    my ($group, $name);
    my @work;

    open $in, "<$file"
        or die print ": open file error[" . $file . "]: $!";

    # 1行目
    my $one = <$in>;
    (undef, $group, undef, $name) = split(/,/, $one);
    $group = "" unless (defined $group);
    $name = "" unless (defined $name);
    $group = decode($utf8, $group);
    $name = decode($utf8, $name);

    # 2行目
    my $two = <$in>;

    # ヘッダ
    $output .= $header;

    while (defined(my $line = <$in>)) {

        chomp($line);
        next if ($line eq "");
        $line = decode($enc, $line);

        ($date, $week, $begin, $inf, undef,
         undef, undef, undef, undef, undef, $end) = split(/,/, $line);

        next unless ((defined $date) || ($date eq ""));
        # 始業時間
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
        $common = add_time($begin, $end, @commontime);
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
        $over = add_time($begin, $end, @overtime);
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
        $late = add_time($begin, $end, @latetime);
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
        push(@work, $diff);
        $worktime += $diff;
    } # while
    close $in;

    $common_sum = 0.0 unless (defined $common_sum);
    $over_sum = 0.0 unless (defined $over_sum);
    $late_sum = 0.0 unless (defined $late_sum);
    $holiday_sum = 0.0 unless (defined $holiday_sum);
    $holi_late_sum = 0.0 unless (defined $holi_late_sum);
    $worktime = 0.0 unless (defined $worktime);

    $output .= "\n";
    $output .= "通常" . $sep . $common_sum . "\n";
    $output .= "残業" . $sep . $over_sum . "\n";
    $output .= "深夜" . $sep . $late_sum . "\n";
    $output .= "休日" . $sep . $holiday_sum . "\n";
    $output .= "休日+深夜" . $sep . $holi_late_sum . "\n";
    $output .= "\n合計時間\n";
    $output .= $worktime . "\n";

    print encode($enc, $output);

    # ファイルに出力
    my ($outfn, undef, undef) = fileparse($file, ('.csv'));
    $outfn .= "_" . encode($utf8, $group) unless ($group eq "");
    $outfn .= "_" . encode($utf8, $name) unless ($name eq "");
    $outfn .= ".csv";
    $outfn = Encode::decode_utf8($outfn);
    $outfn =~ s/\s+//g; # 空白削除
    open $out, ">$outfn"
        or die print ": open file error[" . $outfn . "]: $!";
    print $out encode($enc, $output);
    close $out;
}

sub conv_hour($)
{
    my $time = shift;
    my ($h, $m);
    my $result;

    return undef if (!defined $time) || ($time eq "");

    ($h, $m) = split(/:/, $time); # 時分分割
    if (!defined $h || !defined $m) {
        print "format error\n";
        return undef;
    }
    # 時
    $h = $hconv{$h} if (exists $hconv{$h});
    $result = $h . ":" . $m;

    return $result;
}

sub conv_min($)
{
    my $time = shift;
    my ($h, $m);
    my $round;
    my $result;

    return undef if (!defined $time) || ($time eq "");

    ($h, $m) = split(/:/, $time); # 時分分割
    if (!defined $h || !defined $m) {
        print "format error\n";
        return undef;
    }
    # 分
    $round = round_time($m); # 丸めちゃう

    if (defined $mconv{$round}) {
        $result = $h . "." . $mconv{$round};
    } else { # ここにくることはない
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

# @timelstが範囲内の場合時間を加算する
sub add_time($$@)
{
    my $begin = shift;
    my $end = shift;
    my @timelst = @_;
    my $addtime = 0;

    return undef if (!defined $begin || !defined $end);

    foreach my $time (@timelst) {
        if ($begin <= ($time - 0.25) && $time <= $end) {
            $addtime += 0.25;
        }
    }
    #print "time=$time ";
    return $addtime;
}

# 引数チェック
if ($#ARGV < 0) {
    print "no argument\n";
    exit($stathash{'EX_NG'});
}

unless (-f "$ARGV[0]") {
    print "no file";
}

# ファイル読み込み処理する
read_file("$ARGV[0]");

exit($stathash{'EX_OK'});
