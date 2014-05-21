
The clipper.py file included in this distribution is a **very old** Python translation of the Clipper Library. 
I've given up updating this version of Clipper because, since the Python code is interpreted, it's about 
100 times slower than compiled versions of Clipper (see below).

Alternatively, Maxime Chalon <maxime.chalon@gmail.com> has written a Python extension module for Clipper:
https://sites.google.com/site/maxelsbackyard/home/pyclipper
This module provides a Python interface to the C++ compiled Clipper Library (and runs about 100 times faster than clipper.py).

