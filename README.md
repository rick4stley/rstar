# rstar
R* Tree implementation in Lua
## Description
A [R* Tree](https://infolab.usc.edu/csci599/Fall2001/paper/rstar-tree.pdf) (pronounced r star tree) is a data structure which is meant to store n-dimensional boxes, in a way that makes queries, like range searches, very efficient.
This is a variant of the [R-Tree](http://www-db.deis.unibo.it/courses/SI-LS/papers/Gut84.pdf): the key difference is that R* Tree optimizes its structure over time. As items are inserted or deleted, this tree will get more robust and nodes will overlap less.
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

Creates a new instance of R* Tree, using a table of `settings` as argument.
Here's the list of `settings`' valid fields:
* `M` the maximum number of children per node; must be a integer number >= than 4. The default value is 20.
* `m` the minimum number of children per node; must be a integer number >= than 2 and <= than M/2. The default value is 8 (40% of M).
* `reinsert_p` the number of children to reinsert when their quantity exeeds M; must be a integer number >= than 1 and < than M. The default value is 6 (30% of M).
* `reinsert_method` the method used to decide which `reinsert_p` children should be reinserted; `'weighted'` uses the medium point of all children, and `'normal'` uses the node's center instead. The default value is `'normal'`
* `choice_p`

#### rstar:insert(item)

#### rstar:delete(id)

#### rstar:search(s, result)

#### rstar:select(p, result)

#### rstar:draw([only_leaves])

