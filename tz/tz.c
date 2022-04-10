#include <stdio.h>
#include <time.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/time.h>

enum {
    E_NAME = 0,
    E_TZ,
    E_TIMEDIFF,
    E_SUMMERTIME,
    E_MAXTZTABLE
};

// https://jp.cybozu.help/ja/g42/admin/appdx/timezone/
// 2015-8-16
// http://pecl.php.net/package/timezonedb
char *tz_table[][E_MAXTZTABLE] = {
    { "カイロ            ", "Africa/Cairo",                   "UTC+02:00", "         " },
    { "カサブランカ      ", "Africa/Casablanca",              "UTC+00:00", "UTC+01:00" },
    { "ヨハネスブルグ    ", "Africa/Johannesburg",            "UTC+02:00", "         " },
    { "ラゴス            ", "Africa/Lagos",                   "UTC+01:00", "         " },
    { "ナイロビ          ", "Africa/Nairobi",                 "UTC+03:00", "         " },
    { "ビントフック      ", "Africa/Windhoek",                "UTC+01:00", "UTC+02:00" },
    { "アンカレッジ      ", "America/Anchorage",              "UTC-09:00", "UTC-08:00" },
    { "ブエノスアイレス  ", "America/Argentina/Buenos_Aires", "UTC-03:00", "         " },
    { "アスンシオン      ", "America/Asuncion",               "UTC-04:00", "UTC-03:00" },
    { "ボゴタ            ", "America/Bogota",                 "UTC-05:00", "         " },
    { "カラカス          ", "America/Caracas",                "UTC-04:30", "         " },
    { "カイエンヌ        ", "America/Cayenne",                "UTC-03:00", "         " },
    { "シカゴ            ", "America/Chicago",                "UTC-06:00", "UTC-05:00" },
    { "チワワ            ", "America/Chihuahua",              "UTC-07:00", "UTC-06:00" },
    { "クイアバ          ", "America/Cuiaba",                 "UTC-04:00", "UTC-03:00" },
    { "デンバー          ", "America/Denver",                 "UTC-07:00", "UTC-06:00" },
    { "ゴッドホープ      ", "America/Godthab",                "UTC-03:00", "UTC-02:00" },
    { "グァテマラ共和国  ", "America/Guatemala",              "UTC-06:00", "         " },
    { "ハリファクス      ", "America/Halifax",                "UTC-04:00", "UTC-03:00" },
    { "インディアナポリス", "America/Indiana/Indianapolis",   "UTC-05:00", "UTC-04:00" },
    { "ラパス            ", "America/La_Paz",                 "UTC-04:00", "         " },
    { "ロサンゼルス      ", "America/Los_Angeles",            "UTC-08:00", "UTC-07:00" },
    { "マナウス          ", "America/Manaus",                 "UTC-04:00", "         " },
    { "メキシコシティー  ", "America/Mexico_City",            "UTC-06:00", "UTC-05:00" },
    { "モンテビデオ      ", "America/Montevideo",             "UTC-03:00", "         " },
    { "ニューヨーク      ", "America/New_York",               "UTC-05:00", "UTC-04:00" },
    { "フェニックス      ", "America/Phoenix",                "UTC-07:00", "         " },
    { "レジャイナ        ", "America/Regina",                 "UTC-06:00", "         " },
    { "バハカリフォルニア", "America/Santa_Isabel",           "UTC-08:00", "UTC-07:00" },
    { "サンチアゴ        ", "America/Santiago",               "UTC-03:00", "         " },
    { "サンパウロ        ", "America/Sao_Paulo",              "UTC-03:00", "UTC-02:00" },
    { "セントジョンズ    ", "America/St_Johns",               "UTC-03:30", "UTC-02:30" },
    { "ティフアナ        ", "America/Tijuana",                "UTC-08:00", "UTC-07:00" },
    { "アルマトイ        ", "Asia/Almaty",                    "UTC+06:00", "         " },
    { "アンマン          ", "Asia/Amman",                     "UTC+02:00", "UTC+03:00" },
    { "バグダッド        ", "Asia/Baghdad",                   "UTC+03:00", "         " },
    { "バクー            ", "Asia/Baku",                      "UTC+04:00", "UTC+05:00" },
    { "バンコク          ", "Asia/Bangkok",                   "UTC+07:00", "         " },
    { "ベイルート        ", "Asia/Beirut",                    "UTC+02:00", "UTC+03:00" },
    { "コロンボ          ", "Asia/Colombo",                   "UTC+05:30", "         " },
    { "ダマスカス        ", "Asia/Damascus",                  "UTC+02:00", "UTC+03:00" },
    { "ダッカ            ", "Asia/Dhaka",                     "UTC+06:00", "         " },
    { "ドバイ            ", "Asia/Dubai",                     "UTC+04:00", "         " },
    { "イルクーツク      ", "Asia/Irkutsk",                   "UTC+08:00", "         " },
    { "エルサレム        ", "Asia/Jerusalem",                 "UTC+02:00", "UTC+03:00" },
    { "カブール          ", "Asia/Kabul",                     "UTC+04:30", "         " },
    { "カムチャッカ      ", "Asia/Kamchatka",                 "UTC+12:00", "         " },
    { "カラチ            ", "Asia/Karachi",                   "UTC+05:00", "         " },
    { "カトマンズ        ", "Asia/Kathmandu",                 "UTC+05:45", "         " },
    { "コルカタ          ", "Asia/Kolkata",                   "UTC+05:30", "         " },
    { "クラスノヤルスク  ", "Asia/Krasnoyarsk",               "UTC+07:00", "         " },
    { "マガダン          ", "Asia/Magadan",                   "UTC+10:00", "         " },
    { "ノボシビルスク    ", "Asia/Novosibirsk",               "UTC+06:00", "         " },
    { "ラングーン        ", "Asia/Rangoon",                   "UTC+06:30", "         " },
    { "リヤド            ", "Asia/Riyadh",                    "UTC+03:00", "         " },
    { "ソウル            ", "Asia/Seoul",                     "UTC+09:00", "         " },
    { "北京              ", "Asia/Shanghai",                  "UTC+08:00", "         " },
    { "シンガポール      ", "Asia/Singapore",                 "UTC+08:00", "         " },
    { "台北              ", "Asia/Taipei",                    "UTC+08:00", "         " },
    { "タシケント        ", "Asia/Tashkent",                  "UTC+05:00", "         " },
    { "トビリシ          ", "Asia/Tbilisi",                   "UTC+04:00", "         " },
    { "テヘラン          ", "Asia/Tehran",                    "UTC+03:30", "UTC+04:30" },
    { "東京              ", "Asia/Tokyo",                     "UTC+09:00", "         " },
    { "ウランバートル    ", "Asia/Ulaanbaatar",               "UTC+08:00", "UTC+09:00" },
    { "ウラジオストク    ", "Asia/Vladivostok",               "UTC+10:00", "         " },
    { "ヤクーツク        ", "Asia/Yakutsk",                   "UTC+09:00", "         " },
    { "エカテリンブルグ  ", "Asia/Yekaterinburg",             "UTC+05:00", "         " },
    { "エレバン          ", "Asia/Yerevan",                   "UTC+04:00", "         " },
    { "アゾレス諸島      ", "Atlantic/Azores",                "UTC-01:00", "UTC-00:00" },
    { "カボベルデ共和国  ", "Atlantic/Cape_Verde",            "UTC-01:00", "         " },
    { "レイキャビク      ", "Atlantic/Reykjavik",             "UTC+00:00", "         " },
    { "南ジョージア島    ", "Atlantic/South_Georgia",         "UTC-02:00", "         " },
    { "アデレード        ", "Australia/Adelaide",             "UTC+09:30", "UTC+10:30" },
    { "ブリスベン        ", "Australia/Brisbane",             "UTC+10:00", "         " },
    { "ダーウィン        ", "Australia/Darwin",               "UTC+09:30", "         " },
    { "ホバート          ", "Australia/Hobart",               "UTC+10:00", "UTC+11:00" },
    { "パース            ", "Australia/Perth",                "UTC+08:00", "         " },
    { "シドニー          ", "Australia/Sydney",               "UTC+10:00", "UTC+11:00" },
    { "ベルリン          ", "Europe/Berlin",                  "UTC+01:00", "UTC+02:00" },
    { "ブダペスト        ", "Europe/Budapest",                "UTC+01:00", "UTC+02:00" },
    { "イスタンブール    ", "Europe/Istanbul",                "UTC+02:00", "UTC+03:00" },
    { "キエフ            ", "Europe/Kiev",                    "UTC+02:00", "UTC+03:00" },
    { "ロンドン          ", "Europe/London",                  "UTC+00:00", "UTC+01:00" },
    { "ミンスク          ", "Europe/Minsk",                   "UTC+03:00", "         " },
    { "モスクワ          ", "Europe/Moscow",                  "UTC+03:00", "         " },
    { "パリ              ", "Europe/Paris",                   "UTC+01:00", "UTC+02:00" },
    { "ワルシャワ        ", "Europe/Warsaw",                  "UTC+01:00", "UTC+02:00" },
    { "モーリシャス      ", "Indian/Mauritius",               "UTC+04:00", "         " },
    { "アピーア          ", "Pacific/Apia",                   "UTC+13:00", "UTC+14:00" },
    { "オークランド      ", "Pacific/Auckland",               "UTC+12:00", "UTC+13:00" },
    { "フィジー          ", "Pacific/Fiji",                   "UTC+12:00", "UTC+13:00" },
    { "ガダルカナル      ", "Pacific/Guadalcanal",            "UTC+11:00", "         " },
    { "ホノルル          ", "Pacific/Honolulu",               "UTC-10:00", "         " },
    { "ポートモレスビー  ", "Pacific/Port_Moresby",           "UTC+10:00", "         " },
    { "トンガタプ        ", "Pacific/Tongatapu",              "UTC+13:00", "         " },
    { "UTC               ", "UTC",                            "UTC+00:00", "         " },
    { "UTC-10            ", "Etc/GMT+10",                     "UTC-10:00", "         " },
    { "UTC-11            ", "Etc/GMT+11",                     "UTC-11:00", "         " },
    { "UTC-12            ", "Etc/GMT+12",                     "UTC-12:00", "         " },
    { "UTC-1             ", "Etc/GMT+1",                      "UTC-01:00", "         " },
    { "UTC-2             ", "Etc/GMT+2",                      "UTC-02:00", "         " },
    { "UTC-3             ", "Etc/GMT+3",                      "UTC-03:00", "         " },
    { "UTC-4             ", "Etc/GMT+4",                      "UTC-04:00", "         " },
    { "UTC-5             ", "Etc/GMT+5",                      "UTC-05:00", "         " },
    { "UTC-6             ", "Etc/GMT+6",                      "UTC-06:00", "         " },
    { "UTC-7             ", "Etc/GMT+7",                      "UTC-07:00", "         " },
    { "UTC-8             ", "Etc/GMT+8",                      "UTC-08:00", "         " },
    { "UTC-9             ", "Etc/GMT+9",                      "UTC-09:00", "         " },
    { "UTC               ", "Etc/GMT",                        "UTC+00:00", "         " },
    { "UTC+10            ", "Etc/GMT-10",                     "UTC+10:00", "         " },
    { "UTC+11            ", "Etc/GMT-11",                     "UTC+11:00", "         " },
    { "UTC+12            ", "Etc/GMT-12",                     "UTC+12:00", "         " },
    { "UTC+1             ", "Etc/GMT-1",                      "UTC+01:00", "         " },
    { "UTC+2             ", "Etc/GMT-2",                      "UTC+02:00", "         " },
    { "UTC+3             ", "Etc/GMT-3",                      "UTC+03:00", "         " },
    { "UTC+4             ", "Etc/GMT-4",                      "UTC+04:00", "         " },
    { "UTC+5             ", "Etc/GMT-5",                      "UTC+05:00", "         " },
    { "UTC+6             ", "Etc/GMT-6",                      "UTC+06:00", "         " },
    { "UTC+7             ", "Etc/GMT-7",                      "UTC+07:00", "         " },
    { "UTC+8             ", "Etc/GMT-8",                      "UTC+08:00", "         " },
    { "UTC+9             ", "Etc/GMT-9",                      "UTC+09:00", "         " }
};

time_t my_timegm(struct tm *tm);
void print_local(time_t t);
void print_tm(struct tm *t);
time_t before_7days_1(time_t t);
time_t before_7days_2(time_t t);
time_t before_7days_3(time_t t);

time_t my_timegm(struct tm *tm)
{
    time_t ret;
    char *tz;

    tz = getenv("TZ");
    if (tz)
        tz = strdup(tz);
    setenv("TZ", "         ", 1);
    tzset();
    ret = mktime(tm);
    if (tz) {
       setenv("TZ", tz, 1);
       free(tz);
    } else
       unsetenv("TZ");
    tzset();
    return ret;
 }


void print_local(time_t t)
{
    struct tm result = {};
    char str[30];
    localtime_r(&t, &result);
    asctime_r(&result, str);
    str[strlen(str)-1] = '\0';
    printf("%s [%ju]: ",
        str, (uintmax_t)t);
}

void print_tm(struct tm *t)
{
    printf("%04d-%02d-%02d %02d:%02d:%02d\n",
        t->tm_year + 1900,
        t->tm_mon,
        t->tm_mday,
        t->tm_hour,
        t->tm_min,
        t->tm_sec);

    printf("tm_sec=%d, tm_min=%d, tm_hour=%d, tm_mday=%d, tm_mon=%d, tm_year=%d\n",
           t->tm_sec, t->tm_min, t->tm_hour, t->tm_mday, t->tm_mon, t->tm_year);
    printf("tm_wday=%d, tm_yday=%d, tm_isdst=%d, tm_gmtoff=%ld, tm_zone=%s\n",
           t->tm_wday, t->tm_yday, t->tm_isdst, t->tm_gmtoff, t->tm_zone);
}

time_t before_7days_1(time_t t)
{
    time_t result = 0;
    time_t before = 7*24*60*60;
    result = t - before;
    printf("now: ");
    print_local(t);
    printf("before: ");
    print_local(result);

    return result;
}

time_t before_7days_2(time_t t)
{
    struct timeval result;
    struct timeval before;
    struct timeval now;
    timerclear(&result);
    timerclear(&before);
    timerclear(&now);

    before.tv_sec = 7*24*60*60;
    now.tv_sec = t;
    timersub(&now, &before, &result);
    printf("now: ");
    print_local(t);
    printf("before: ");
    print_local(result.tv_sec);

    return result.tv_sec;
}

time_t before_7days_3(time_t t)
{
    time_t result = 0;
    struct tm before = {};

    localtime_r(&t, &before);
    before.tm_mday -= 7;
    result = mktime(&before);
    printf("now: ");
    print_local(t);
    printf("before: ");
    print_local(result);

    return result;
}

int main(int argc, char *argv[])
{
    time_t now = 0;
    struct tm local = {};
    struct tm gmt = {};

    now = time(NULL);
    localtime_r(&now, &local);
    gmtime_r(&now, &gmt);

    printf("localtime\n");
    print_tm(&local);
    printf("\n");
    printf("gmtime\n");
    print_tm(&gmt);
    printf("\n");
    printf("time_t now=%lu\n", now);
    time_t loc_time = mktime(&local);
    printf("struct tm local mktime=%lu\n", (unsigned long)loc_time);
    time_t gm_time = my_timegm(&gmt);
    printf("struct tm gmt timegm=%lu\n", (unsigned long)gm_time);
    printf("(local-gmt)/60/60=%ld\n", (long)((loc_time-gm_time)/60/60));

    char tz_env[40] = {0};
    struct tm local_tm = {};
    size_t tz_table_size = sizeof(tz_table)/sizeof(tz_table[E_MAXTZTABLE]);
    for (int i = 0; i < tz_table_size; i++) {
        strncpy(tz_env, "TZ=", sizeof(tz_env));
        strncat(tz_env, tz_table[i][E_TZ], sizeof(tz_env) - sizeof("TZ="));
        putenv(tz_env);
        tzset();
        localtime_r(&now, &local_tm);
        int gmtoff = local_tm.tm_gmtoff;
        int isdst = local_tm.tm_isdst;
        print_local(now);
        char sign = '+';
        if (gmtoff < 0) {
            sign = '-';
            gmtoff *= -1;
        }
        int hour = gmtoff / 3600;
        int min  = (gmtoff % 3600) / 60;
        printf("%s %s %s ",
            tz_table[i][E_NAME], tz_table[i][E_TIMEDIFF], tz_table[i][E_SUMMERTIME]);
        printf("%c%02d:%02d(%s): %d isdst=%d\n",
            sign, hour, min, local_tm.tm_zone, gmtoff, isdst);
    }

    time_t before1 = before_7days_1(now);
    printf("%lu, %d\n", before1, (int)difftime(now, before1));
    time_t before2 = before_7days_2(now);
    printf("%lu, %d\n", before2, (int)difftime(now, before2));
    time_t before3 = before_7days_3(now);
    printf("%lu, %d\n", before3, (int)difftime(now, before3));

    return EXIT_SUCCESS;
}
