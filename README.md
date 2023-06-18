# Page Six

A better social link-sharing site.

## TODO

- [ ] model relationships defined:
  * 1 User -> 1 Comment
  * many comments -> 1 Post
  * many posts -> 1 Subreddit
  * many subreddits -> 1 Subreddits listing
- [ ] add [Constraints](https://leafo.net/lapis/reference/models.html#constraints) to models (?)
- [ ] add table indexes (hot-sorted subreddit posts, homepage, user accounts)
- [ ] user accounts w/[CSRF](https://leafo.net/lapis/reference/utilities.html#csrf-protection )
- [ ] Individual Pages
  - [ ] `homepage`
  - [ ] `/subreddits/` `/subreddits/mine` listings pages
  - [ ] `subreddit` landing page
    - [ ] Sorting parameter (`/r/.../top/?t=year`, `/popular`, `new`, `rising`, `controversial`)
    - [ ] use [Pagination](https://leafo.net/lapis/reference/models.html#pagination)
  - [ ] `/r/.../submit` (per-subreddit)
  - [ ] `/login`, `/logout`, `/password`
  - [ ] `prefs`, `settings`
- [ ] RSS feed import/sync (per-subreddit?)
- [ ] API (https://reddit.com/dev/api/)

## Development

From the root directory:

```
docker run \
    -dti \
    -v "./data:/var/data" \
    -v "./app:/var/www" \
    -e LAPIS_ENV="development" \
    -p 8080:80 \
    --name pagesix \
    --platform=linux/amd64 \
    karai17/lapis-centos:latest
```

Then, visit: http://localhost:8080/

# Notes

* [Reddit Archive](https://github.com/reddit-archive/reddit) - for CSS and HTML inspiration
* Built using [Lapis](https://leafo.net/lapis/) and [OpenResty](https://openresty.org/) in [Lua v5.1](https://www.lua.org/manual/5.1/)
