#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <linux/keyboard.h>

/*
 * Sample vendor-supplied boot time recovery trigger detector.
 * Returns 0 if the shift key is pressed, 1 otherwise.
 */

int main()
{
    int fd;
    char shift_state = 6;

    if ((fd = open("/dev/console", O_RDONLY)) < 0) {
        exit(EXIT_FAILURE);
    }
    if (ioctl(fd, TIOCLINUX, &shift_state) < 0) {
        exit(EXIT_FAILURE);
    }

    exit((shift_state & (1 << KG_SHIFT)) ? EXIT_SUCCESS : EXIT_FAILURE);
}
