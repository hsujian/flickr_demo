"use strict"

Pool = require('generic-pool').Pool
line_reader = require 'line-reader'
fs = require 'fs'

places_file = './data/places.json'
photos_file = './data/photos.json'
photo_list_file = './data/photo.txt'

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

wget_pool = Pool
  name: 'wget'
  create: (cb) ->
    wget = require 'wget'
    cb null, wget
  destroy: (client) ->
  max: 4
  idleTimeoutMillis : 30000
  log : true

get_image_path = (id) ->
  id = +id
  la = parseInt(id/100000000)
  other = parseInt(id%100000000)
  lb = parseInt(other/10000)
  "data/image/#{la}/#{lb}"

prepare_image_path = (id) ->
  mkdirp = require 'mkdirp'
  img_path = get_image_path id
  mkdirp.sync img_path
  return img_path

adjust_image_url = (url) ->
  idx = url.indexOf '_b.jpg'
  if idx > 0
    return url.substr(0, idx) + '.jpg'
  idx = url.indexOf '_o.jpg'
  if idx > 0
    return url.substr(0, idx) + '.jpg'
  return off

wget_image = (url, id) ->
  img_path = get_image_path id
  img_filename = "#{img_path}/#{id}.jpg"
  if fs.existsSync img_filename
    return off
  prepare_image_path id
  wget_pool.acquire (err, wget) ->
    throw new Error err if err
    img = wget.download url, img_filename
    img.on 'error', (err) ->
      console.log "wget_image error #{err}"
      url = adjust_image_url url
      wget_image url, id if url
    img.on 'end', ->
      wget_pool.release wget
  on

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
  return unless res.photos.total
  for photo in res.photos.photo[0...100]
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
    return "#{prefix}#{photo.originalsecret}_o.#{photo.originalformat}"
  "#{prefix}#{photo.secret}_b.jpg"

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
        fs.writeFile photos_file, JSON.stringify(photos, null, '\t'), ->
          if pool.waitingClientsCount() < 1
            cb(photos)
  if pool.waitingClientsCount() < 1
    cb photos
  on

load_places (places) ->
  console.log 'get places done'
  load_photos places, (photos) ->
    console.log 'search photos done'
    for woeid, info of photos
      parse_photos info, (photo) ->
        url = get_photo_url photo
        return unless url
        line = "#{photo.id},#{url}\n"
        fs.appendFileSync photo_list_file, line
        #wget_image url, photo.id
    off
