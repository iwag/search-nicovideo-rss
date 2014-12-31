search-nicovideo-rss
====================

新検索β( http://search.nicovideo.jp/api/ ) to RSS convertor

how to work.

```
$ heroku create
$ heroku addon:redistogo
$ git push heroku origin
$ heroku config:set TZ="Asia/Tokyo" RACK_ENV="production" QUERY_TERM="アニメ"
$ open http://$(your heroku url)/rss
```

