#!/usr/bin/python3 -I
# rss.py NAME OUT ERR CMD...: run CMD with stdout to OUT and stderr to ERR, print "NAME rss_kb=N wall_s=S rc=R"
import resource, subprocess, sys, time

name, out, err = sys.argv[1:4]
t = time.time()
with open(out, "wb") as o, open(err, "wb") as e:
    rc = subprocess.run(sys.argv[4:], stdout=o, stderr=e).returncode
rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
print("%s rss_kb=%d wall_s=%.1f rc=%d" % (name, rss, time.time() - t, rc))
