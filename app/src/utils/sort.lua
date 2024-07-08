--- Sort utils
-- @module utils.sort

local os = require("os")

local Sort = {}
Sort.__index = Sort

local function best(a, b)
    -- sort descending by Upvotes
    print("BEST A=" .. a.upvotes .. ", B=" .. b.upvotes)

    return a.upvotes > b.upvotes
end

-- return the difference from val to goal
local function nearest(val, goal)
    goal = goal or 1.0
    print("NEAREST " .. math.abs(val - goal))
    return math.abs(val - goal)
end

local function controversial(a, b)
    -- TODO taking the total number of votes and weighing it by bias, i.e. (up+down) ** (min(up, down)/max(up, down)).


    -- ratio of Upvote:Downvote closest to 1.0
    local a_dist = nearest(a.upvotes - a.downvotes)
    local b_dist = nearest(b.upvotes - b.downvotes)
    print("CONTROVERSIAL A=" .. a_dist .. ", B=" .. b_dist)

    return a_dist < b_dist
end

local function date_to_timestamp(date_str, pattern)
    -- date_str="2004-07-06 20:4:20"
    pattern = pattern or "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"

    local year,month,day,hour,min,sec = date_str:match(pattern)
    local offset = os.time()-os.time(os.date("!*t"))

    local seconds = os.time({
        day=day,
        month=month,
        year=year,
        hour=hour,
        min=min,
        sec=sec
    })+offset

    -- print("TIME: " .. s .. " IN SECONDS IS " .. seconds)
    return seconds
end

local function hot(a, b)
    -- log10 of the score and weighs it against 12 hour periods

    -- log( abs( Upvotes - Downvotes ) + ( age_in_seconds / 45000 ))

    local a_hot = math.log( math.abs( a.upvotes - a.downvotes ) + ( date_to_timestamp(a.age) / 45000 )) -- 43,200 == 12 hours
    local b_hot = math.log( math.abs( b.upvotes - b.downvotes ) + ( date_to_timestamp(b.age) / 45000 ))

    -- print("HOT A=" .. a_hot .. ", B=" .. b_hot)
    return a_hot > b_hot
end

-- local function rising(a, b)
--     -- like "top" except over a shorter time period
--     -- sort descending by Upvotes - Downvotes
--     local a_total = a.upvotes - a.downvotes
--     local b_total = b.upvotes - b.downvotes
--     print("RISING A=" .. a_total .. ", B=" .. b_total)
--     return a_total > b_total
-- end

local function top(a, b)
    -- sort descending by Upvotes - Downvotes
    local a_total = a.upvotes - a.downvotes
    local b_total = b.upvotes - b.downvotes
    print("TOP A=" .. a_total .. ", B=" .. b_total)
    return a_total > b_total
end

-- TODO use enum
-- todo replace if statement with single getfenv(algo) or _g[algo]() call
function Sort:sort(items, algo)
    print("Sorting by " .. algo)

    -- local a = {
    --     best = best,
    --     controversial = controversial,
    --     hot = hot,
    --     -- rising = rising,
    --     top = top,
    -- }

    local arr = {}
    for _,n in pairs(items) do table.insert(arr, n) end
    -- table.sort(arr, a[algo])

    if algo == 'best' then
        table.sort(arr, best)
    elseif algo == 'top' then
        table.sort(arr, top)
    elseif algo == 'controversial' then
        table.sort(arr, controversial)
    -- elseif algo == 'rising' then
    --     table.sort(arr, rising)
    else
        table.sort(arr, hot)
    end

    return arr
end

return Sort