module GenieCacheRedisCache

import Serialization
import GenieCache
using Genie.Context
using Base64
using Jedis


const CACHE_PATH = Ref{String}("genie_cache_")


"""
    cache_path()

Returns the default path of the cache folder.
"""
function cache_path()
  CACHE_PATH[]
end


"""
    cache_path!(cachepath::AbstractString)

Sets the default path of the cache folder.
"""
function cache_path!(cachepath::AbstractString)
  CACHE_PATH[] = cachepath
end


"""
    cache_path(key::Any; dir::String = "") :: String

Computes the path to a cache `key` based on current cache settings.
"""
function cache_path(key::Any; dir::String = "") :: String
  path = joinpath(cache_path(), dir)
  joinpath(path, string(key))
end


#===#
# INTERFACE #


"""
    tocache(key::Any, content::Any; dir::String = "") :: Nothing

Persists `content` onto the file system under the `key` key.
"""
function GenieCache.tocache(key::Any, content::Any; dir::String = "", expiration::Int = GenieCache.cache_duration()) :: Nothing
  io = IOBuffer()
  iob64_encode = Base64EncodePipe(io)
  Serialization.serialize(iob64_encode, content)
  close(iob64_encode)
  Jedis.set(cache_path(string(key), dir = dir), String(take!(io)))

  if expiration > 0
    Jedis.expire(cache_path(string(key), dir = dir), expiration)
  end

  nothing
end


"""
    fromcache(key::Any, expiration::Int; dir::String = "") :: Union{Nothing,Any}

Retrieves from cache the object stored under the `key` key if the `expiration` delta (in seconds) is in the future.
"""
function GenieCache.fromcache(key::Any; dir::String = "", expiration::Int = GenieCache.cache_duration()) :: Union{Nothing,Any}
  filepath = cache_path(string(key), dir = dir)

  io = IOBuffer()
  iob64_decode = Base64DecodePipe(io)
  content = Jedis.get(filepath)

  content === nothing && return nothing

  Base.write(io, content)
  seekstart(io)
  Serialization.deserialize(iob64_decode)
end


"""
    purge(key::Any) :: Nothing

Removes the cache data stored under the `key` key.
"""
function GenieCache.purge(key::Any; dir::String = "") :: Nothing
  Jedis.del(cache_path(GenieCache.cachekey(string(key)), dir = dir))

  nothing
end


"""
    purgeall(; dir::String = "") :: Nothing

Removes all cached data.
"""
function GenieCache.purgeall(; dir::String = "") :: Nothing
  pattern = cache_path() * "/*"
  for key in Jedis.keys(pattern)
    Jedis.del(key)
  end

  nothing
end


function __init__()
  Jedis.set_global_client(;
    host = get(ENV, "GENIE_REDIS_HOST", "127.0.0.1"),
    port = parse(Int, get(ENV, "GENIE_REDIS_PORT", "6379")),
    password = get(ENV, "GENIE_REDIS_PASSWORD", ""),
    username = get(ENV, "GENIE_REDIS_USERNAME", ""),
    database = parse(Int, get(ENV, "GENIE_REDIS_DATABASE", "0")),
  )
end

end
