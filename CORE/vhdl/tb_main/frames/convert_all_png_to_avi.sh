#!/usr/bin/env bash

ffmpeg -framerate 50 -i frame_%04d.png -codec copy -y test.avi

