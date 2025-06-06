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

--
-- EntityIndex
--
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

--
-- Commands
--
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

--
-- Cosmos
--
local Cosmos = class {
  init = function(self)
    -- Index of all entities
    self.mainIndex = EntityIndex({})

    -- A mapping of query (key) to entity index for that query (value)
    self.indexes = {}

    -- Mapping of event name (key) to systems triggered by that event (value)
    self.systems = {}

    -- Commands passed to systems for modifying cosmos state (i.e., entities and components)
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
    table.sort(components)
    local query = table.concat(components, '|')

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
}

--
-- Module
--
return Cosmos
