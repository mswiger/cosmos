--[[
Copyright (c) 2025 Michael Swiger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]--

local unpack = table.unpack or unpack

---Simple class constructor
local function class(klass)
  klass = klass or {}

  klass.__index = klass
  klass.init = klass.init or function() end

  return setmetatable(klass, {
    __call = function(c, ...)
      local obj = setmetatable({}, c)
      obj:init(...)
      return obj
    end,
  })
end

---Generate a query string from the list of components
---@param components any[] list of components from which to generate the query string
---@return string # the query string generated
local function generateQuery(components)
  local queryComponents = {}
  for _, component in ipairs(components) do
    table.insert(queryComponents, tostring(component))
  end
  table.sort(queryComponents)
  return table.concat(queryComponents, '|')
end

---Manages an index of entities and their components. This is used to cache the results of entity queries.
---@class EntityIndex
---
---@field components any[] list of component types by which the entities are indexed
---@field entities table list of components in the index
---@field contains table<table, boolean> a hashmap to speed up checking for entities that exist in the index
---
---Check whether the given entity exists in the index.
---@field hasEntity fun(self: self, entity: table): boolean
---Check whether an entity with the given components exists in the index.
---@field matchesEntity fun(self: self, entity: table): boolean
---Add an entity to the index.
---@field addEntity fun(self: self, entity: table)
---Remove an entity from the index.
---@field removeEntity fun(self: self, entity: table) bla
---
---@overload fun(components: table): EntityIndex
local EntityIndex = class {
  init = function(self, components)
    self.components = components
    self.entities = {}
    self.contains = {}
  end,

  hasEntity = function (self, entity)
    return self.contains[entity] ~= nil
  end,

  matchesEntity = function(self, entity)
    for _, component in ipairs(self.components) do
      if entity[component] == nil then
        return false
      end
    end

    return true
  end,

  addEntity = function(self, entity)
    if self:hasEntity(entity) then
      return
    end

    table.insert(self.entities, entity)
    self.contains[entity] = true
  end,

  removeEntity = function(self, entity)
    if not self:hasEntity(entity) then
      return
    end

    local removeIndex = -1
    for i = 1, #self.entities do
      if self.entities[i] == entity then
        removeIndex = i
        break
      end
    end

    if removeIndex > 0 then
      table.remove(self.entities, removeIndex)
    end

    self.contains[entity] = nil
  end,
}

---Class that manages enqueuing commands to be executed on entities. This includes spawning and despawning entities as
---well as attaching and removing components from existing entities. When the execute method is ran, the commands are
---executed.
---@class Commands
---
---@field entitiesToSpawn table[] queue that manages entities to be spawned
---@field entitiesToDespawn table[] queue that manages entities to be despawned
---@field componentsToAttach table[] queue that manages components to be attached
---@field componentsToDetach table[] queue that manages components to be detached
---
---Enqueues an entity to be spawned when the commands are executed.
---@field spawn fun(self: self, entity: table): table
---
---Enqueues an entity to be despawned when the commands are executed.
---@field despawn fun(self: self, entity: table)
---
---Enqueues a list of components to be attached to the given entity when the commands are executed.
---@field attachComponents fun(self: self, entity: table, components: table)
---
---Enqueues a list of components to be detached to the given entity when the commands are executed.
---@field detatchComponents fun(self: self, entity: table, ...)
---
---Executes the commands that have been enqueued since the last execution. This clears each queue that it executes.
---@field execute fun(self: self)
---
---@overload fun(cosmos: Cosmos): Commands
local Commands = class {
  init = function(self, cosmos)
    self.cosmos = cosmos
    self.entitiesToSpawn = {}
    self.entitiesToDespawn = {}
    self.componentsToAttach = {}
    self.componentsToDetach = {}
  end,

  spawn = function(self, entity)
    table.insert(self.entitiesToSpawn, entity)
  end,

  despawn = function(self, entity)
    table.insert(self.entitiesToDespawn, entity)
  end,

  attachComponents = function(self, entity, components)
    if self.componentsToAttach[entity] == nil then
      self.componentsToAttach[entity] = {}
    end

    for name, value in pairs(components) do
      self.componentsToAttach[entity][name] = value
    end
  end,

  detachComponents = function(self, entity, ...)
    if self.componentsToDetach[entity] == nil then
      self.componentsToDetach[entity] = {}
    end

    for _, component in ipairs({...}) do
      table.insert(self.componentsToDetach[entity], component)
    end
  end,

  execute = function(self)
    for i = 1, #self.entitiesToSpawn do
      self.cosmos:spawn(self.entitiesToSpawn[i])
      self.entitiesToSpawn[i] = nil
    end

    for i = 1, #self.entitiesToDespawn do
      self.cosmos:despawn(self.entitiesToDespawn[i])
      self.entitiesToDespawn[i] = nil
    end

    for entity, components in pairs(self.componentsToAttach) do
      self.cosmos:attachComponents(entity, components)
      self.componentsToAttach[entity] = nil
    end

    for entity, components in pairs(self.componentsToDetach) do
      self.cosmos:detachComponents(entity, unpack(components))
      self.componentsToDetach[entity] = nil
    end
  end
}

---Class that represents a "cosmos," more traditionally referred to as the "world."
---@class Cosmos
---
---@field mainIndex EntityIndex index of all entities in the cosmos
---@field indexes table<string, EntityIndex> a mapping of the query to the entity index for that query
---@field systems table<any, table> a mapping of event type to systems triggered by that event
---@field commands Commands commands used for modifying cosmos state
---
---Enqueues an entity to be spawned when the commands are executed.
---@field spawn fun(self: self, entity: table): table
---
---Enqueues an entity to be despawned when the commands are executed.
---@field despawn fun(self: self, entity: table)
---
---Enqueues a list of components to be attached to the given entity when the commands are executed.
---@field attachComponents fun(self: self, entity: table, components: table)
---
---Enqueues a list of components to be detached to the given entity when the commands are executed.
---@field detatchComponents fun(self: self, entity: table, ...)
---
---Adds the given systems to be executed when the given event is emitted.
---@field addSystems fun(self: self, event: any, ...)
---
---Executes the systems that are attached to the given event, passing the given varargs to each executed system.
---@field emit fun(self: self, event: any, ...)
---
---@overload fun(): Cosmos
local Cosmos = class {
  init = function(self)
    self.mainIndex = EntityIndex({})
    self.indexes = {}
    self.systems = {}
    self.commands = Commands(self)
  end,

  spawn = function(self, entity)
    self.mainIndex:addEntity(entity)

    for _, index in pairs(self.indexes) do
      if index:matchesEntity(entity) then
        index:addEntity(entity)
      end
    end
  end,

  despawn = function(self, entity)
    self.mainIndex:removeEntity(entity)

    for _, index in pairs(self.indexes) do
      if index:hasEntity(entity) then
        index:removeEntity(entity)
      end
    end
  end,

  attachComponents = function(self, entity, components)
    for name, value in pairs(components) do
      entity[name] = value
    end

    for _, index in pairs(self.indexes) do
      if index:matchesEntity(entity) then
        index:addEntity(entity)
      end
    end
  end,

  detachComponents = function(self, entity, ...)
    for _, component in ipairs({...}) do
      entity[component] = nil
    end

    for _, index in pairs(self.indexes) do
      if index:hasEntity(entity) and not index:matchesEntity(entity) then
        index:removeEntity(entity)
      end
    end
  end,

  addSystems = function(self, event, ...)
    if self.systems[event] == nil then
      self.systems[event] = {}
    end

    local systems = { ... }
    for _, system in pairs(systems) do
      table.insert(self.systems[event], system)
    end
  end,

  emit = function(self, event, ...)
    if self.systems[event] == nil then
      return
    end

    for _, system in ipairs(self.systems[event]) do
      local entities

      -- A query can either be a list of components or a key-value mapping of query name to components.
      -- In the former case, only a single set of entities is returned. In the latter case, each query's
      -- results is stored in the returned entities table where the name of the query is the key.
      -- If no query is present, then all entities will be provided.
      if system.query == nil then
        entities = self.mainIndex.entities
      elseif system.query[1] ~= nil then
        entities = self:queryEntities(system.query)
      else
        for name, query in pairs(system.query) do
          entities[name] = self:queryEntities(query)
        end
      end

      system:process(entities or {}, self.commands, ...)
    end

    self.commands:execute()
  end,

  queryEntities = function(self, components)
    local query = generateQuery(components)

    if self.indexes[query] == nil then
      self.indexes[query] = EntityIndex(components)

      for _, entity in pairs(self.mainIndex.entities) do
        if self.indexes[query]:matchesEntity(entity) then
          self.indexes[query]:addEntity(entity)
        end
      end
    end

    return self.indexes[query].entities
  end,
}

--
-- Module
--
return Cosmos
