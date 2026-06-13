--- Comment action
-- @module action.comment

local Comments = require("models.comments")
local Posts = require("src.models.posts")


return {
    before = function(self)
        local comment = Comments:find(self.params.comment_id)
        if not comment then
            return self:write({ redirect_to = self:url_for("homepage") })
        end

        -- Permalink view: the focused comment + its full reply subtree, plus up
        -- to `?context=N` ancestor comments above it (depth-ordered, rendered by
        -- the shared comments fragment). `context` defaults to 0 (no ancestors).
        self.comments = Comments:permalink_thread(comment.id, self.params.context)
        self.focused_comment_id = comment.id

        -- Resolve the parent post for the page header (title/url/author).
        local post_data = Posts:find(comment.post_id)
        if post_data then
            -- posts has no user_name column; resolve the author via the relation.
            local author = post_data:get_user()
            self.user_name = author and author.user_name
            self.title = post_data["title"]
            self.url = post_data["url"]
            self.created_at = post_data["created_at"]
            self.post_id = comment.post_id
        end
    end,

    GET = function(self)
        return { render = "comment" }
    end,
}
