--- Approval-queue policy: should a user's new post/comment be held for a
--- moderator, or published immediately?
-- @module utils.queue

local Users = require("models.users")
local Privileges = require("src.utils.privileges")

local Queue = {}

--- Whether `user`'s content in `forum` should be held for moderator approval.
-- Trusted contributors -- anyone who can approve in this forum (its moderators
-- and owners) and site admins -- post directly. Everyone else is held only
-- while they are brand new (trust level "new", i.e. reputation below the member
-- threshold); once they earn reputation they post freely.
-- @tparam table user a users row (needs `.id` and `.reputation`)
-- @tparam[opt] table forum the destination forum row
-- @treturn boolean
function Queue.should_hold(user, forum)
	if not user then
		return true
	end
	if forum and Privileges.can(user.id, forum, "approve") then
		return false
	end
	return Users:trust_level(user.reputation) == "new"
end

return Queue
