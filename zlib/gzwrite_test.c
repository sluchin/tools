#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <zlib.h>

#define BUF_SIZE 1048576 //16777215 //1048576
#define FILENAME "test.gz"

int main(int argc, char *argv[])
{
    char buf[BUF_SIZE] = {0};
    for (int i = 0; i < sizeof(buf); i++) {
        //buf[i] = 'a' + (i % 26);
        srand(i);
        buf[i] = (unsigned char)(rand() % 0xFF);
    }

    gzFile zp = NULL;
    zp = gzopen(FILENAME, "w6");
    if (!zp) {
        fprintf(stderr, "gzopen error\n");
        return EXIT_FAILURE;
    }

    fprintf(stderr, "gzwrite: size=%zu\n", sizeof(buf));
    int retval = gzwrite(zp, buf, sizeof(buf));
    if (retval < 0) {
        fprintf(stderr, "gzwrite error\n");
        return EXIT_FAILURE;
    }
    fprintf(stderr, "gzwrite=%d\n", retval);

    if (zp)
        gzclose(zp);
    zp = NULL;

    return EXIT_SUCCESS;
}
