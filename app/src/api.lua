--- API URLs
-- @module src.api

function api(app)

    app:get("/api", function(self) return "NOTE: The API doesn't work but most endpoints exist" end)

    -- NOTE: the following endpoints aren't included:
    --      collections, emoji, flair, gold, listings, live threads,
    --      private messages, new modmail, modnote, multis, widgets, wiki

    -- account
    app:get("/api/v1/me",          function(self) return "/api/v1/me" end)
    app:get("/api/v1/me/blocked",  function(self) return "/api/v1/me/blocked" end)
    app:get("/api/v1/me/friends",  function(self) return "/api/v1/me/friends" end)
    app:get("/api/v1/me/karma",    function(self) return "/api/v1/me/karma" end)
    -- NOTE: lapis doens't support :patch
    -- app:patch("/api/v1/me/prefs",  function(self) return "/api/v1/me/prefs" end)
    app:get("/api/v1/me/trophies", function(self) return "/api/v1/me/trophies" end)
    app:get("/prefs/blocked",      function(self) return "/prefs/blocked" end)
    app:get("/prefs/friends",      function(self) return "/prefs/friends" end)
    app:get("/prefs/messaging",    function(self) return "/prefs/messaging" end)
    app:get("/prefs/trusted",      function(self) return "/prefs/trusted" end)
    app:get("/prefs/where",        function(self) return "/prefs/where" end)

    -- captcha
    app:get("/api/needs_captcha", function(self) return "/api/needs_captcha" end)

    -- links & comments
    app:post("/api/comment",              function(self) return "/api/comment" end)
    app:post("/api/del",                  function(self) return "/api/del" end)
    app:post("/api/editusertext",         function(self) return "/api/editusertext" end)
    app:post("/api/event_post_time",      function(self) return "/api/event_post_time" end)
    app:post("/api/follow_post",          function(self) return "/api/follow_post" end)
    app:post("/api/hide",                 function(self) return "/api/hide" end)
    app:get("/api/info",                  function(self) return "/api/info" end)
    app:post("/api/lock",                 function(self) return "/api/lock" end)
    app:post("/api/marknsfw",             function(self) return "/api/marknsfw" end)
    app:get("/api/morechildren",          function(self) return "/api/morechildren" end)
    app:post("/api/report",               function(self) return "/api/report" end)
    app:post("/api/report_award",         function(self) return "/api/report_award" end)
    app:post("/api/save",                 function(self) return "/api/save" end)
    app:get("/api/saved_categories",      function(self) return "/api/saved_categories" end)
    app:post("/api/sendreplies",          function(self) return "/api/sendreplies" end)
    app:post("/api/set_contest_mode",     function(self) return "/api/set_contest_mode" end)
    app:post("/api/set_subreddit_sticky", function(self) return "/api/set_subreddit_sticky" end)
    app:post("/api/set_suggested_sort",   function(self) return "/api/set_suggested_sort" end)
    app:post("/api/spoiler",              function(self) return "/api/spoiler" end)
    app:post("/api/store_visits",         function(self) return "/api/store_visits" end)
    app:post("/api/submit",               function(self) return "/api/submit" end)
    app:post("/api/unhide",               function(self) return "/api/unhide" end)
    app:post("/api/unlock",               function(self) return "/api/unlock" end)
    app:post("/api/unmarknsfw",           function(self) return "/api/unmarknsfw" end)
    app:post("/api/unsave",               function(self) return "/api/unsave" end)
    app:post("/api/unspoiler",            function(self) return "/api/unspoiler" end)
    app:post("/api/vote",                 function(self) return "/api/vote" end)

    -- listings
    app:get("/best", function(self) return "/best" end)
    app:get("/by_id/names", function(self) return "/by_id/names" end)
    app:get("/comments/article", function(self) return "/comments/article" end)
    app:get("/controversial", function(self) return "/controversial" end)
    app:get("/duplicates/article", function(self) return "/duplicates/article" end)
    app:get("/hot", function(self) return "/hot" end)
    app:get("/new", function(self) return "/new" end)
    app:get("/random", function(self) return "/random" end)
    app:get("/rising", function(self) return "/rising" end)
    app:get("/top", function(self) return "/top" end)
    app:get("/sort", function(self) return "/sort" end)

    -- misc
    app:get("/api/saved_media_text", function(self) return "/api/saved_media_text" end)
    app:get("/api/v1/scopes",        function(self) return "/api/v1/scopes" end)

    -- moderation
    app:get("/about/edited", function(self) return "/about/edited" end)
    app:get("/about/log", function(self) return "/about/log" end)
    app:get("/about/modqueue", function(self) return "/about/modqueue" end)
    app:get("/about/reports", function(self) return "/about/reports" end)
    app:get("/about/spam", function(self) return "/about/spam" end)
    app:get("/about/unmoderated", function(self) return "/about/unmoderated" end)
    app:get("/about/location", function(self) return "/about/location" end)
    app:post("/api/accept_moderator_invite", function(self) return "/api/accept_moderator_invite" end)
    app:post("/api/approve", function(self) return "/api/approve" end)
    app:post("/api/distinguish", function(self) return "/api/distinguish" end)
    app:post("/api/ignore_reports", function(self) return "/api/ignore_reports" end)
    app:post("/api/leavecontributor", function(self) return "/api/leavecontributor" end)
    app:post("/api/leavemoderator", function(self) return "/api/leavemoderator" end)
    app:post("/api/mute_message_author", function(self) return "/api/mute_message_author" end)
    app:post("/api/remove", function(self) return "/api/remove" end)
    app:post("/api/show_comment", function(self) return "/api/show_comment" end)
    app:post("/api/snooze_reports", function(self) return "/api/snooze_reports" end)
    app:post("/api/unignore_reports", function(self) return "/api/unignore_reports" end)
    app:post("/api/unmute_message_author", function(self) return "/api/unmute_message_author" end)
    app:post("/api/unsnooze_reports", function(self) return "/api/unsnooze_reports" end)
    app:post("/api/update_crowd_control_level", function(self) return "/api/update_crowd_control_level" end)
    app:get("/stylesheet", function(self) return "/stylesheet" end)

    -- multis
    app:get("/api/filter/filterpath",           function(self) return "/api/filter/filterpath" end)
    app:get("/api/filter/filterpath/r/srname",  function(self) return "/api/filter/filterpath/r/srname" end)
    app:post("/api/multi/copy",                 function(self) return "/api/multi/copy" end)
    app:get("/api/multi/mine",                  function(self) return "/api/multi/mine" end)
    app:get("/api/multi/user/username",         function(self) return "/api/multi/user/username" end)
    app:delete("/api/multi/multipath",          function(self) return "/api/multi/multipath" end)
    app:get("/api/multi/multipath",             function(self) return "/api/multi/multipath" end)
    app:post("/api/multi/multipath",            function(self) return "/api/multi/multipath" end)
    app:put("/api/multi/multipath",             function(self) return "/api/multi/multipath" end)
    app:get("/api/multi/multipath/description", function(self) return "/api/multi/multipath/description" end)
    app:put("/api/multi/multipath/description", function(self) return "/api/multi/multipath/description" end)
    app:delete("/api/multi/multipath/r/srname", function(self) return "/api/multi/multipath/r/srname" end)
    app:get("/api/multi/multipath/r/srname",    function(self) return "/api/multi/multipath/r/srname" end)
    app:put("/api/multi/multipath/r/srname",    function(self) return "/api/multi/multipath/r/srname" end)

    -- search
    app:get("/search", function(self) return "/search" end)

    -- subreddits
    app:get("/about/banned",                  function(self) return "/about/banned" end)
    app:get("/about/contributors",            function(self) return "/about/contributors" end)
    app:get("/about/moderators",              function(self) return "/about/moderators" end)
    app:get("/about/muted",                   function(self) return "/about/muted" end)
    app:get("/about/wikibanned",              function(self) return "/about/wikibanned" end)
    app:get("/about/wikicontributors",        function(self) return "/about/wikicontributors" end)
    app:get("/about/where",                   function(self) return "/about/where" end)
    app:post("/api/delete_sr_banner",         function(self) return "/api/delete_sr_banner" end)
    app:post("/api/delete_sr_header",         function(self) return "/api/delete_sr_header" end)
    app:post("/api/delete_sr_icon",           function(self) return "/api/delete_sr_icon" end)
    app:post("/api/delete_sr_img",            function(self) return "/api/delete_sr_img" end)
    app:get("/api/recommend/sr/srnames",      function(self) return "/api/recommend/sr/srnames" end)
    app:post("/api/search_reddit_names",      function(self) return "/api/search_reddit_names" end)
    app:post("/api/search_subreddits",        function(self) return "/api/search_subreddits" end)
    app:post("/api/site_admin",               function(self) return "/api/site_admin" end)
    app:get("/api/submit_text",               function(self) return "/api/submit_text" end)
    app:get("/api/subreddit_autocomplete",    function(self) return "/api/subreddit_autocomplete" end)
    app:get("/api/subreddit_autocomplete_v2", function(self) return "/api/subreddit_autocomplete_v2" end)
    app:post("/api/subreddit_stylesheet",     function(self) return "/api/subreddit_stylesheet" end)
    app:post("/api/subscribe",                function(self) return "/api/subscribe" end)
    app:post("/api/upload_sr_img",            function(self) return "/api/upload_sr_img" end)
    app:get("/api/v1/subreddit/post_requirements", function(self) return "/api/v1/subreddit/post_requirements" end)
    app:get("/r/subreddit/about",             function(self) return "/r/subreddit/about" end)
    app:get("/r/subreddit/about/edit",        function(self) return "/r/subreddit/about/edit" end)
    app:get("/r/subreddit/about/rules",       function(self) return "/r/subreddit/about/rules" end)
    app:get("/r/subreddit/about/traffic",     function(self) return "/r/subreddit/about/traffic" end)
    app:get("/sidebar",                       function(self) return "/sidebar" end)
    app:get("/sticky",                        function(self) return "/sticky" end)
    app:get("/subreddits/default",            function(self) return "/subreddits/default" end)
    app:get("/subreddits/gold",               function(self) return "/subreddits/gold" end)
    app:get("/subreddits/mine/contributor",   function(self) return "/subreddits/mine/contributor" end)
    app:get("/subreddits/mine/moderator",     function(self) return "/subreddits/mine/moderator" end)
    app:get("/subreddits/mine/streams",       function(self) return "/subreddits/mine/streams" end)
    app:get("/subreddits/mine/subscriber",    function(self) return "/subreddits/mine/subscriber" end)
    app:get("/subreddits/mine/where",         function(self) return "/subreddits/mine/where" end)
    app:get("/subreddits/new",                function(self) return "/subreddits/new" end)
    app:get("/subreddits/popular",            function(self) return "/subreddits/popular" end)
    app:get("/subreddits/search",             function(self) return "/subreddits/search" end)
    app:get("/subreddits/where",              function(self) return "/subreddits/where" end)
    app:get("/users/new",                     function(self) return "/users/new" end)
    app:get("/users/popular",                 function(self) return "/users/popular" end)
    app:get("/users/search",                  function(self) return "/users/search" end)
    app:get("/users/where",                   function(self) return "/users/where" end)

    -- users
    app:post("/api/block_user",               function(self) return "/api/block_user" end)
    app:post("(/r/:subreddit)/api/friend",    function(self) return "/api/friend" end)
    app:post("/api/report_user",              function(self) return "/api/report_user" end)
    app:post("/api/setpermissions",           function(self) return "/api/setpermissions" end)
    app:post("(/r/:subreddit)/api/unfriend",  function(self) return "/api/unfriend" end)
    app:get("/api/user_data_by_account_ids",  function(self) return "/api/user_data_by_account_ids" end)
    app:get("/api/username_available",        function(self) return "/api/username_available" end)
    app:delete("/api/v1/me/friends/username", function(self) return "/api/v1/me/friends/username" end)
    app:get("/api/v1/me/friends/username",    function(self) return "/api/v1/me/friends/username" end)
    app:put("/api/v1/me/friends/username",    function(self) return "/api/v1/me/friends/username" end)
    app:get("/api/v1/user/username/trophies", function(self) return "/api/v1/user/username/trophies" end)
    app:get("/user/username/:where",          function(self) return "/user/username/about" end)

    return app
end
return api