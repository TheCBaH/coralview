/* Converts the subset of VCD the fixtures use (scopes, wire vars, scalar and vector changes) to FST with
   libfst's writer. Build and run through vcd2fst.sh. */
#include <fstapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct var { char id[32]; fstHandle h; int width; };

static struct var vars[256];
static int nvars;

static struct var *find(const char *id)
{
    for (int i = 0; i < nvars; i++)
        if (strcmp(vars[i].id, id) == 0)
            return &vars[i];
    fprintf(stderr, "unknown id %s\n", id);
    exit(1);
}

static void change(void *w, const char *id, const char *bits)
{
    struct var *v = find(id);
    char buf[1024];
    int n = (int)strlen(bits);
    char pad = (bits[0] == 'x' || bits[0] == 'z') ? bits[0] : '0';
    if (n > v->width || v->width >= (int)sizeof buf) {
        fprintf(stderr, "bad value for %s\n", id);
        exit(1);
    }
    memset(buf, pad, v->width - n);
    memcpy(buf + v->width - n, bits, n);
    buf[v->width] = 0;
    fstWriterEmitValueChange(w, v->h, buf);
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: vcd2fst in.vcd out.fst\n");
        return 2;
    }
    FILE *in = fopen(argv[1], "r");
    void *w = fstWriterCreate(argv[2], 1);
    char line[4096], a[1100], b[64], c[64], d[64], e[64];
    if (!in || !w)
        return 1;
    fstWriterSetTimescale(w, -12);
    while (fgets(line, sizeof line, in)) {
        if (sscanf(line, "$scope %63s %63s", a, b) == 2) {
            fstWriterSetScope(w, FST_ST_VCD_MODULE, b, NULL);
        } else if (!strncmp(line, "$upscope", 8)) {
            fstWriterSetUpscope(w);
        } else if (sscanf(line, "$var %63s %63s %63s %63s", a, b, c, d) == 4) {
            struct var *v = &vars[nvars++];
            snprintf(v->id, sizeof v->id, "%s", c);
            v->width = atoi(b);
            v->h = fstWriterCreateVar(w, FST_VT_VCD_WIRE, FST_VD_IMPLICIT, v->width, d, 0);
        } else if (line[0] == '#') {
            fstWriterEmitTimeChange(w, strtoull(line + 1, NULL, 10));
        } else if (line[0] == 'b' && sscanf(line + 1, "%1099s %63s", a, e) == 2) {
            change(w, e, a);
        } else if (strchr("01xzXZ", line[0]) && sscanf(line + 1, "%1099s", a) == 1) {
            char s[2] = { line[0], 0 };
            change(w, a, s);
        }
    }
    fstWriterClose(w);
    return 0;
}
