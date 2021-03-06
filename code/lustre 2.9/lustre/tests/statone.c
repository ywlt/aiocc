/*
 * GPL HEADER START
 *
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 only,
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License version 2 for more details (a copy is included
 * in the LICENSE file that accompanied this code).
 *
 * You should have received a copy of the GNU General Public License
 * version 2 along with this program; If not, see
 * http://www.gnu.org/licenses/gpl-2.0.html
 *
 * GPL HEADER END
 */
/*
 * Copyright (c) 2003, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2014, Intel Corporation.
 */
/*
 * This file is part of Lustre, http://www.lustre.org/
 * Lustre is a trademark of Sun Microsystems, Inc.
 */

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <lustre_ioctl.h>

int main(int argc, char **argv)
{
    struct obd_ioctl_data data = { 0 };
    char rawbuf[8192], parent[4096], *buf = rawbuf, *base, *t;
    int max = sizeof(rawbuf), fd, offset, rc;

    if (argc != 2) {
        printf("usage: %s filename\n", argv[0]);
        return 1;
    }

    base = argv[1];
    t = strrchr(base, '/');
    if (!t) {
        strcpy(parent, ".");
        offset = -1;
    } else {
        strncpy(parent, base, t - base);
        offset = t - base - 1;
    }

    fd = open(parent, O_RDONLY);
    if (fd < 0) {
        printf("open(%s) error: %s\n", parent, strerror(errno));
        exit(errno);
    }

    data.ioc_version = OBD_IOCTL_VERSION;
    data.ioc_len = sizeof(data);
    if (offset >= 0)
        data.ioc_inlbuf1 = base + offset + 2;
    else
        data.ioc_inlbuf1 = base;
    data.ioc_inllen1 = strlen(data.ioc_inlbuf1) + 1;
    
    if (obd_ioctl_pack(&data, &buf, max)) {
        printf("ioctl_pack failed.\n");
        exit(1);
    }
    
    rc = ioctl(fd, IOC_MDC_LOOKUP, buf);
    if (rc < 0) {
        printf("ioctl(%s/%s) error: %s\n", parent,
               data.ioc_inlbuf1, strerror(errno));
        exit(errno);
    }

    return 0;
}
