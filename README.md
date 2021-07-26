# rstar
R* Tree implementation in Lua
## Description
A [R* Tree](https://infolab.usc.edu/csci599/Fall2001/paper/rstar-tree.pdf) (pronounced r star tree) is a data structure which is meant to store n-dimensional boxes, in a way that makes queries, like range searches, very efficient.
This is a variant of the [R-Tree](http://www-db.deis.unibo.it/courses/SI-LS/papers/Gut84.pdf): the key difference is that R* Trees optimize their structure over time. As items are inserted or deleted, this tree will get more robust and nodes will overlap the least.
This implementation in particular works with *2D AABBs (Axis-Aligned Bounding-Boxes)*.

### What's this good for?
  :heavy_check_mark: Represent infinite worlds, as this structure has no fixed boundaries
  
  :heavy_check_mark: Storing mostly static objects: the trade off for quality of the structure, is insertion and deletion speed
  
  :heavy_check_mark: Drawing applications: selection of shapes is vary fast (with single clicks and selection areas as well)
  
  :heavy_check_mark: Game developement: store obstacles with a wide range of sizes to detect collisions

## How to use
At the top of your main script, require [rstar.lua](rstar.lua?raw=1) as follows:

```lua
rstar = require "rstar"
```
## Class reference

#### rstar.new(settings)

Creates a new instance of R* Tree, getting the table settings as argument
