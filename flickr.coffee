"use strict"

Pool = require('generic-pool').Pool
line_reader = require 'line-reader'
fs = require 'fs'
wget = require 'wget'

places_file = './data/places.json'
photos_file = './data/photos.json'

throw new Error 'unset FLICKR_API_KEY' unless process.env.FLICKR_API_KEY
throw new Error 'unset FLICKR_API_SECRET' unless process.env.FLICKR_API_SECRET

pool = Pool
  name: 'flickr'
  create: (cb) ->
    Flickr = require('flickr').Flickr
    flickr = new Flickr process.env.FLICKR_API_KEY,
      process.env.FLICKR_API_SECRET
    cb null, flickr
  destroy: (client) ->
  max: 1
  idleTimeoutMillis : 30000
  log : true

get_image = (logo, id)->
  img = wget.download logo, "logo/#{id}.jpg"
  img.on 'error', (err) ->
    console.log err

parse_places = (res, cb) ->
  return false unless res.stat == 'ok'
  return unless res.places.total
  total = +res.places.total
  for place in res.places.place
    continue if total > 1 and +place.place_type_id != 7
    cb place
  on

get_places = (location, cb) ->
  params = query: location
  pool.acquire (err, client) ->
    throw new Error err if err
    client.executeAPIRequest "flickr.places.find", params, false, (err, res) ->
      pool.release client

      throw new Error err if err
      cb res

parse_photos = (res, cb) ->
  return false unless res.stat == 'ok'
  return unless res.total
  for photo in res.photos.photo
    cb photo
  on
search_photos = (place, cb) ->
  api = 'flickr.photos.search'
  params =
    privacy_filter: 1
    woe_id: place.woeid
    extras: 'original_format'
    accuracy: 11
  pool.acquire (err, client) ->
    throw new Error err if err
    client.executeAPIRequest api, params, false, (err, res) ->
      pool.release client

      throw new Error err if err
      cb place, res

get_photo_url = (photo) ->
  return unless photo.ispublic
  domain = "farm#{photo.farm}.staticflickr.com"
  prefix = "http://#{domain}/#{photo.server}/#{photo.id}_"
  if photo.originalsecret
    return "#{prefix}_#{photo.originalsecret}_o.#{photo.originalformat}"
  "#{prefix}_#{photo.secret}_b.jpg"

load_places = (cb)->
  if fs.existsSync places_file
    places = require places_file
    cb(places)
    return on

  places = {}
  line_reader.eachLine './data/loc.txt', (loc) ->
    get_places loc, (res) ->
      places[loc] = res
      if pool.waitingClientsCount() < 1
        fs.writeFile places_file, JSON.stringify(places, null, '\t'), ->
          cb(places)

  on

load_photos = (places, cb)->
  photos = {}
  if fs.existsSync photos_file
    photos = require photos_file

  for name,place of places
    parse_places place, (p) ->
      return if photos[p.woeid]
      console.log "#{p.woeid} #{p.woe_name} #{p._content}"
      search_photos p, (p, photos_info) ->
        console.log "#{p.woeid} ok"
        photos[p.woeid] = photos_info
        if pool.waitingClientsCount() < 1
          fs.writeFile photos_file, JSON.stringify(photos, null, '\t'), ->
            cb(photos)
        else
          fs.writeFile photos_file, JSON.stringify(photos, null, '\t')
  if pool.waitingClientsCount() < 1
    cb photos
  on

load_places (places) ->
  console.log 'get places done'
  load_photos places, (photos) ->
    console.log 'search photos done'
