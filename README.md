# attoc-docker
Generates TOC files for the Turtle Beach Audiotron

This Docker image is intended to be run on a NAS box which does not have a proper Perl environment to install all the dependencies needed by attoc.pl (A Perl script written by Jay Grizzard, which scans a directory for music files and generates a table-of-contents file for an AudioTron. The script can be obtained at http://www.lupine.org/attoc.pl)

Use it like:
```
docker run --name attoc -v /volume2/music/:/music  -it eddie303/attoc 
```
where /volume2/music is the share containing music files.
