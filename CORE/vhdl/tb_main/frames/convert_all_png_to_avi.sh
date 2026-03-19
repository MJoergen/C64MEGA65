#!/usr/bin/env bash

ffmpeg -r 50 -i frame_%03d.png -codec copy test.avi

