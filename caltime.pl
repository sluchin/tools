#!C:\Perl\bin\perl -w

##
# 勤務時間を計算する.
#
# 使い方
# caltime.pl ファイル
#
# 入力
# 6/1 9:00 20:30
# 出力
# 6/1 9.00 20.50 1.5 10
#
# $Date: 2012/10/01 01:10:15 $
# $Author: t-higashi $
# $Revision: 1.10 $
# $Id: caltime.pl,v 1.10 2012/10/01 01:10:15 t-higashi Exp $
#

use strict;
use warnings;
use File::Basename;

our $VERSION = do { my @r = ( q$Revision: 1.10 $ =~ /\d+/g ); sprintf "%d." . "%02d" x $#r, @r if (@r) };
my $progname = basename($0);

# ステータス
my %stathash = (
    'EX_OK' => 0, # 正常終了
    'EX_NG' => 1, # 異常終了
);

# 15分単位で集計
my @unitmin = ( 00, 15, 30, 45 );

# 分を時間に変換(9:15 は 9.25)
my %convhash = ( "00" => ".00",
                 "15" => ".25",
                 "30" => ".50",
                 "45" => ".75",
);

# ミクロスの休み時間は以下です。(by 小部さん)
# 12:00～13:00
# 17:00～17:30
# 22:00～22:30
# 休憩時間(こいつが範囲内のときは0.25ずつ加算していくと休憩時間がでる)
my @resttime = ( 12.25, 12.50, 12.75, 13.00, # 12:00～13:00
                 17.25, 17.50,               # 17:00～17:30
                 22.25, 22.50,               # 22:00～22:30
);

sub read_file($)
{
    my $file = shift;
    my $in;
    my ($date, $begin, $end, $rest);
    my ($diff, $worktime);
    my @work;

    open $in, "<$file"
        or die print ": open file error[" . $file . "]: $!";

    while (defined(my $line = <$in>)) {

        #print $line;
        chomp($line);
        next if ($line eq "");

        ($date, $begin, $end) = split(/ /, $line);
        print "$date " if (defined $date);
        print "\t";

        # はじまりの分処理
        if (defined $begin) {
            $begin = conv_time($begin);
            print "$begin ";
        }
        print "\t";
        # 終わりの分処理
        if (defined $end) {
            $end = conv_time($end);
            print "$end ";
        } else {
            $end = "18.50";
        }
        print "\t";

        # 休憩時間取得
        $rest = rest_time($begin, $end);
        print "$rest " if (defined $rest);
        print "\t";

        # 勤務時間の計算
        $diff = ($end - $begin) - $rest;
        print $diff . "\n";
        push(@work, $diff);
        $worktime += $diff;
    } # while
    close $in;

    print "\n合計時間\n";
    print "$worktime\n";
    if (260 < $worktime) {
        print "\n働きすぎです(・ω・)\n";
    } elsif (200 == $worktime) {
        print "\nキリ番げっと(`Щ´)\n";
    } elsif (160 <= $worktime && $worktime < 260) {
        print "\nまあまあですね(・Х・)\n";
    } elsif ($worktime < 160) {
        print "\nたりない・・・(￣□￣;)\n";
    }
}

sub conv_time($)
{
    my $time = shift;
    my ($h, $m);
    my $round;
    my $result;

    return undef unless defined $time;

    ($h, $m) = split(/:/, $time); # 時分分割
    if (!defined $h || !defined $m) {
        print "format error\n";
        return undef;
    }
    $round = round_time($m); # 丸めちゃう
    if (defined $convhash{$round}) {
        $result = $h . $convhash{$round};
    } else { # ここにくることはないよね
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

sub rest_time($$)
{
    my $begin = shift;
    my $end = shift;
    my $time = 0;

    return undef if (!defined $begin || !defined $end);

    foreach my $rest (@resttime) {
        if ($begin <= ($rest - 0.25) && $rest <= $end) {
            $time += 0.25;
        }
    }
    #print "time=$time ";
    return $time;
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
