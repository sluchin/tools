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
  round_time add_time val2str recursive_dir
  $sep $basetime $common_sum $over_sum $late_sum
  $holiday_sum $holi_late_sum $worktime);

# セパレータ
our $sep = ",";

# 9:00から出勤
our $basetime = 9.00;

# 15分単位で集計
my @unitmin = ( 00, 15, 30, 45 );

# 深夜残業(22:00〜5:00) ※休憩時間も含む
my @latetime = (
    22.25, 22.50, 22.75, 23.00,    # 22:00〜23:00
    23.25, 23.50, 23.75, 24.00,    # 23:00〜00:00
    24.25, 24.50, 24.75, 25.00,    # 00:00～01:00
    25.25, 25.50, 25.75, 26.00,    # 01:00〜02:00
    26.25, 26.50, 26.75, 27.00,    # 02:00〜03:00
    27.25, 27.50, 27.75, 28.00,    # 03:00〜04:00
    28.25, 28.50, 28.75, 29.00,    # 04:00〜05:00
    46.25, 46.50, 46.75, 47.00,    # 22:00〜23:00
    47.25, 47.50, 47.75, 48.00,    # 23:00〜00:00
    48.25, 48.50, 48.75, 49.00,    # 00:00～01:00
    49.25, 49.50, 49.75, 50.00,    # 01:00〜02:00
    50.25, 50.50, 50.75, 51.00,    # 02:00〜03:00
    51.25, 51.50, 51.75, 52.00,    # 03:00〜04:00
    52.25, 52.50, 52.75, 53.00,    # 04:00〜05:00
);

# 休憩時間
my @resttime = (
    12.25, 12.50, 12.75, 13.00,    # 12:00～13:00
    18.75, 19.00,                  # 18:30～19:00
    21.75, 22.00,                  # 21:30～22:00
    24.25, 24.50, 24.75, 25.00,    # 00:00～01:00
    27.75, 28.00,                  # 03:30～04:00
    32.75, 33.00,                  # 08:30～09:00
    36.25, 36.50, 36.75, 37.00,    # 12:00～13:00
    42.75, 43.00,                  # 18:30～19:00
    45.75, 46.00,                  # 21:30～22:00
    48.25, 48.50, 48.75, 49.00,    # 00:00～01:00
    51.75, 52.00,                  # 03:30～04:00
    56.75, 56.00,                  # 08:30～09:00
);

# 合計時間
our ( $common_sum,  $over_sum,      $late_sum );
our ( $holiday_sum, $holi_late_sum, $worktime );

##
# 通常時間を算出
#
sub common_time {
    my $offset = shift;
    my @result;
    my $time = $basetime + $offset;
    my $add  = 0;
    while ( $add < 8.0 ) {
        $time += 0.25;
        unless ( grep { $_ == $time } @resttime ) {
            $add += 0.25;
            push( @result, $time );
        }
    }
    return @result;
}

##
# 残業時間を算出
#
sub over_time {
    my @common = @_;
    my @result;
    my $add  = 0;
    my $time = $common[-1];
    while ( $add < ( 24.0 - 8.0 ) ) {
        $time += 0.25;
        unless ( grep { $_ == $time } @resttime ) {
            $add += 0.25;
            push( @result, $time );
        }
    }
    return @result;
}

##
# 計算
#
sub calc_sum {
    my ( $begin, $end, $offset, $holiday ) = @_;
    my ( $common, $over, $late, $rest );
    my ( $diff, $output );
    my @diff;

    # 通常時間
    my @commontime = common_time($offset);
    @diff = grep {
        !{ map { $_, 1 } @latetime }->{$_}
    } @commontime;
    $common = add_time( $begin, $end, @diff );
    if ( defined $common ) {
        if ($holiday) {
            $holiday_sum += $common;
        }
        else {
            $common_sum += $common;
            $output .= "$common";
        }
    }
    $output .= $sep;

    # 残業時間
    my @overtime = over_time(@commontime);
    @diff = grep {
        !{ map { $_, 1 } @latetime }->{$_}
    } @overtime;
    $over = add_time( $begin, $end, @diff );
    if ( defined $over ) {
        if ($holiday) {

            # 休日出勤の場合, 残業は関係ない
            $holiday_sum += $over;
        }
        else {
            $over_sum += $over;
            $output .= "$over";
        }
    }
    $output .= $sep;

    # 深夜残業
    @diff = grep {
        !{ map { $_, 1 } @resttime }->{$_}
    } @latetime;
    $late = add_time( $begin, $end, @diff );
    if ( defined $late ) {
        if ($holiday) {

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
    if ($holiday) {
        $common += $over if ( defined $over );
        $output .= $common;
    }
    $output .= $sep;

    # 休日出勤+深夜
    if ($holiday) {
        $output .= $late if ( defined $late );
    }
    $output .= $sep;

    # 休憩時間取得
    $rest = add_time( $begin, $end, @resttime );
    $output .= "$rest" if ( defined $rest );
    $output .= $sep;

    # 勤務時間の計算
    if ( defined $begin && defined $end && defined $rest ) {
        $diff = ( $end - $begin ) - $rest;
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
    my ( $time, $offset ) = @_;
    my ( $h, $m );
    my $hconv;
    my $result;

    return undef if ( !defined $time ) || ( $time eq "" );

    ( $h, $m ) = split( /:/, $time );    # 時分分割
    if ( !defined $h || !defined $m ) {
        printf "format error[$time]\n";
        return undef;
    }

    # 時
    $hconv = $h;
    $h += 0;
    for ( my $i = 0 ; $i < ( $basetime + $offset + 1 ) ; $i++ ) {
        if ( $i == $h ) {
            $hconv = sprintf( "%02d", $i + 24 );
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
    my ( $time, $offset ) = @_;
    my ( $h, $m );
    my $round;
    my $result;
    my %mconv = (
        "00" => "00",
        "15" => "25",
        "30" => "50",
        "45" => "75"
    );

    return undef if ( !defined $time ) || ( $time eq "" );

    ( $h, $m ) = split( /:/, $time );    # 時分分割
    if ( !defined $h || !defined $m ) {
        print "format error[$time]\n";
        return undef;
    }

    # 丸める
    $round = round_time($m);

    if ( $h < ( $basetime + $offset ) ) {
        $h = $basetime + $offset;
        $m = 0;
    }
    else {
        $m = $mconv{$round} if ( exists $mconv{$round} );
    }
    $result = $h . "." . $m;

    return $result;
}

##
# 丸める
#
sub round_time {
    my $time = shift;

    return "00" unless ( defined $time );

    for ( my $i = 0 ; $i < @unitmin ; $i++ ) {
        if ( $time <= $unitmin[$i] ) {
            return "$unitmin[$i]";
        }
    }
    return "00";
}

##
# 範囲内の場合,時間を加算
#
sub add_time {
    my $begin   = shift;
    my $end     = shift;
    my @timelst = @_;
    my $addtime = 0;

    return undef if ( !defined $begin || !defined $end );
    return undef if ( ( $begin eq "" ) || ( $end eq "" ) );

    foreach my $time (@timelst) {
        if ( $begin <= ( $time - 0.25 ) && $time <= $end ) {
            $addtime += 0.25;
        }
    }
    return $addtime;
}

##
# 時間を文字列に変換する
#
sub val2str {
    my $time = shift;
    my ( $h, $m );
    my $result;
    my %mconv = (
        "00" => "00",
        "25" => "15",
        "50" => "30",
        "75" => "45"
    );

    $h = sprintf "%d", ( $time % 24 );
    $m = sprintf "%d", ( $time * 100 );
    $m = substr $m, -2, 2;
    $m = $mconv{$m} if ( exists $mconv{$m} );
    $result = sprintf( "%02s:%02s", $h, $m );
    return $result;
}

##
# ディレクトリ配下のファイルをリストにして返す
#
sub recursive_dir {
    my $dir    = shift;
    my @result = ();

    find sub {
        my $file = $_;
        my $path = $File::Find::name;
        push( @result, $path ) if ( $file =~ /^\d{6}\.csv$/ );
    }, $dir;

    return @result;
}

1;

__END__

