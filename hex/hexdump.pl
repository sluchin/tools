#!/usr/bin/perl -w

use strict;
use warnings;
use File::Basename;

our $VERSION = "0.1";
my $progname = basename($0);

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

##
# 複数のファイルを開く
#
sub readfiles {
    my @files = @_;

    foreach my $file (@files) {

        # ファイル開く
        open my $in, "<$file"
          or die print "open file error: $!: ", $file, "\n";

        # 1バイトずつ読み込む
        print_hex_from_file($in);

        # ファイルを閉じる
        close $in;
    }
}

##
# 16進数で表示 (文字列)
#
sub print_hex_from_string {
    my $string = shift;
    my @strings;
    my ( $addr, $count );

    print
      "Address  :  0 1  2 3  4 5  6 7  8 9  A B  C D  E F 0123456789ABCDEF\n";
    print
      "--------   ---- ---- ---- ---- ---- ---- ---- ---- ----------------\n";

    $addr = $count = 0;
    for (my $i = 0; $i < length($string); $i++) {
        my $code = substr($string, $i, 1);
        printf( "%08X : ", $addr ) if ( $count == 0 );
        printf( "%02X%s", unpack( "C", $code ), ( $count % 2 ) ? " " : "" );

        $strings[$count] = $code;
        $count++;

        if ( $count == 16 ) {
            $addr += $count;
            print_string(@strings);
            $count = 0;
            @strings = ();
            print "\n";
        }
    }
    if ( $count != 0 ) {
        my $left = 16 - $count;
        while ($left) {
            printf( "  %s", ( $left % 2 ) ? " " : "" );
            $left--;
        }
        print_string(@strings);
        printf "\n";
    }
}

##
# 16進数で表示 (ファイル)
#
sub print_hex_from_file {
    my $file = shift;
    my ( $code, @strings );
    my ( $addr, $count );
    binmode($file);

    print
      "Address  :  0 1  2 3  4 5  6 7  8 9  A B  C D  E F 0123456789ABCDEF\n";
    print
      "--------   ---- ---- ---- ---- ---- ---- ---- ---- ----------------\n";

    $addr = $count = 0;
    while ( read( $file, $code, 1 ) ) {
        printf( "%08X : ", $addr ) if ( $count == 0 );
        printf( "%02X%s", unpack( "C", $code ), ( $count % 2 ) ? " " : "" );

        $strings[$count] = $code;
        $count++;

        if ( $count == 16 ) {
            $addr += $count;
            print_string(@strings);
            $count = 0;
            @strings = ();
            print "\n";
        }
    }
    if ( $count != 0 ) {
        my $left = 16 - $count;
        while ($left) {
            printf( "  %s", ( $left % 2 ) ? " " : "" );
            $left--;
        }
        print_string(@strings);
        printf "\n";
    }
}

##
# 文字列を表示する
#
sub print_string {
    my @strings = @_;

    for my $string (@strings) {
        if ( $string lt ' ' || '~' lt $string ) {
            print ".";
        }
        else {
            printf( "%s", $string );
        }
    }
}

##
# 日時を表示する
#
sub print_datetime {
    my ( $sec, $min, $hour, $mday, $mon, $year );
    ( $sec, $min, $hour, $mday, $mon, $year, undef, undef, undef ) =
      localtime(time);
    print sprintf(
        "[%04d-%02d-%02d %02d:%02d:%02d]\n",
        $year + 1900,
        $mon + 1, $mday, $hour, $min, $sec
    );
}

# 開始日時表示
print_datetime();

if ( $#ARGV < 0 ) {
    # 標準入力から実行
    print_hex_from_string(<stdin>);
}
else {
    # ファイルから実行
    readfiles("@ARGV");
}

# 終了日時表示
print_datetime();

exit( $stathash{'EX_OK'} );
