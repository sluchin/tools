##
# @file caltime.pm
#
# 勤務時間を計算する.
#
# @author Tetsuya Higashi
# @version $Id$
#

package caltime;

use strict;
use warnings;
use File::Find;

use Exporter;
use base qw(Exporter);
our @EXPORT = qw(calc_sum conv_hour conv_min
                 round_time add_time recursive_dir
                 $sep $basetime $common_sum $over_sum $late_sum
                 $holiday_sum $holi_late_sum $worktime);

# 15分単位で集計
my @unitmin = ( 00, 15, 30, 45 );

# 以下の値が範囲内のときに0.25ずつ加算していくとそれぞれの時間がでる
# 通常時間(9:00〜18：00)
my @commontime = (  9.25,  9.50,  9.75, 10.00,  # 09:00〜10:00
                   10.25, 10.50, 10.75, 11.00,  # 10:00〜11:00
                   11.25, 11.50, 11.75, 12.00,  # 11:00〜12:00
                   12.25, 12.50, 12.75, 13.00,  # 12:00～13:00
                   13.25, 13.50, 13.75, 14.00,  # 13:00〜14:00
                   14.25, 14.50, 14.75, 15.00,  # 14:00〜15:00
                   15.25, 15.50, 15.75, 16.00,  # 15:00〜16:00
                   16.25, 16.50, 16.75, 17.00,  # 16:00〜17:00
                   17.25, 17.50, 17.75, 18.00,  # 17:00〜18:00
);

# 残業時間(18:00〜22:00, 5:00〜8:30)
my @overtime = ( 18.25, 18.50, 18.75, 19.00,    # 18:00〜19:00
                 19.25, 19.50, 19.75, 20.00,    # 19:00〜20:00
                 20.25, 20.50, 20.75, 21.00,    # 20:00〜21:00
                 21.25, 21.50, 21.75, 22.00,    # 21:00〜22:00
                 29.25, 29.50, 29.75, 30.00,    # 05:00〜06:00
                 30.25, 30.50, 30.75, 31.00,    # 06:00〜07:00
                 31.25, 31.50, 31.75, 32.00,    # 07:00〜08:00
                 32.25, 32.50, 32.75, 33.00     # 08:00〜09:00
);

# 深夜残業(22:00〜5:00)
my @latetime = ( 22.25, 22.50, 22.75, 23.00,    # 22:00〜23:00
                 23.25, 23.50, 23.75, 24.00,    # 23:00〜00:00
                 24.25, 24.50, 24.75, 25.00,    # 00:00～01:00
                 25.25, 25.50, 25.75, 26.00,    # 01:00〜02:00
                 26.25, 26.50, 26.75, 27.00,    # 02:00〜03:00
                 27.25, 27.50, 27.75, 28.00,    # 03:00〜04:00
                 28.25, 28.50, 28.75, 29.00,    # 04:00〜05:00
);

# 休憩時間
my @resttime = ( 12.25, 12.50, 12.75, 13.00,    # 12:00～13:00
                 18.75, 19.00,                  # 18:30～19:00
                 21.75, 22.00,                  # 21:30～22:00
                 24.25, 24.50, 24.75, 25.00,    # 00:00～01:00
                 27.75, 28.00,                  # 03:30～04:00
                 32.75, 33.00,                  # 08:30～09:00
);

# セパレータ
our $sep = ",";

# 9:00から出勤
our $basetime = 9.00;

# 合計時間
our ($common_sum, $over_sum, $late_sum);
our ($holiday_sum, $holi_late_sum, $worktime);

##
# 計算
#
sub calc_sum {
    my $begin = shift;
    my $end = shift;
    my $inf = shift;
    my ($common, $over, $late, $rest);
    my ($diff, $output);
    my @diff;

    # 通常時間
    @diff = grep { !{map{$_,1}@resttime }->{$_}}@commontime;
    $common = add_time($begin, $end, @diff);
    if (defined $common) {
        if ((defined $inf) && ($inf eq '出')) {
            $holiday_sum += $common;
        } else {
            $common_sum += $common;
            $output .= "$common"
        }
    }
    $output .= $sep;

    # 残業時間
    @diff = grep { !{map{$_,1}@resttime }->{$_}}@overtime;
    $over = add_time($begin, $end, @diff);
    if (defined $over) {
        if ((defined $inf) && ($inf eq '出')) {
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
        if ((defined $inf) && ($inf eq '出')) {
            # 休日+深夜
            $holi_late_sum += $late;
        } else {
            $late_sum += $late;
            $output .= "$late";
        }
    }
    $output .= $sep;

    # 休日出勤
    if ((defined $inf) && ($inf eq '出')) {
        $common += $over if (defined $over);
        $output .= $common;
    }
    $output .= $sep;

    # 休日出勤+深夜
    if ((defined $inf) && ($inf eq '出')) {
        $output .= $late if (defined $late);
    }
    $output .= $sep;

    # 休憩時間取得
    $rest = add_time($begin, $end, @resttime);
    $output .= "$rest" if (defined $rest);
    $output .= $sep;

    # 勤務時間の計算
    if (defined $begin && defined $end && defined $rest) {
        $diff = ($end - $begin) - $rest;
        $output .= $diff . "\n";
        $worktime += $diff;
    }
    chomp($output);
    $output .= "\n";

    return $output;
}

##
# 時刻を変換(00:00 = 24.00)
#
sub conv_hour {
    my ($time, $offset) = @_;
    my ($h, $m);
    my $hconv;
    my $result;

    return undef if (!defined $time) || ($time eq "");

    ($h, $m) = split(/:/, $time); # 時分分割
    if (!defined $h || !defined $m) {
        printf "format error[$time]\n";
        return undef;
    }
    # 時
    $hconv = $h;
    $h += 0;
    for (my $i = 0; $i < ($basetime + $offset + 1); $i++) {
        if ($i == $h) {
            $hconv = sprintf("%02d", $i + 24);
            last;
        }
    }
    $result = $hconv . ":" . $m;

    return $result;
}

##
# 分を変換(9:15 = 9.25)
#
sub conv_min {
    my ($time, $offset) = @_;
    my ($h, $m);
    my $round;
    my $result;
    my %mconv = ( "00" => "00",
                  "15" => "25",
                  "30" => "50",
                  "45" => "75" );

    return undef if (!defined $time) || ($time eq "");

    ($h, $m) = split(/:/, $time); # 時分分割
    if (!defined $h || !defined $m) {
        print "format error[$time]\n";
        return undef;
    }
    # 丸める
    $round = round_time($m);

    if ($h < ($basetime + $offset)) {
        $h = $basetime + $offset;
        $m = 0;
    } else {
        $m = $mconv{$round} if (exists $mconv{$round});
    }
    $result = $h . "." . $m;

    return $result;
}

##
# 丸める
#
sub round_time {
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
# 範囲内の場合,時間を加算
#
sub add_time {
    my $begin = shift;
    my $end = shift;
    my @timelst = @_;
    my $addtime = 0;

    return undef if (!defined $begin || !defined $end);
    return undef if (($begin eq "") || ($end eq ""));

    foreach my $time (@timelst) {
        if ($begin <= ($time - 0.25) && $time <= $end) {
            $addtime += 0.25;
        }
    }
    return $addtime;
}

##
# ディレクトリ配下のファイルをリストにして返す
#
sub recursive_dir {
    my $dir = shift;
    my @result = ();

    find sub {
        my $file = $_;
        my $path = $File::Find::name;
        push (@result, $path) if ($file =~ /^\d{6}\.csv$/);
    }, $dir;

    return @result;
}

1;

__END__

