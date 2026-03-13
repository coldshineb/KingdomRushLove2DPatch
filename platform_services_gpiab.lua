-- chunkname: @./all-phone/platform_services_gpiab.lua

local log = require("klua.log"):new("platform_services_gpiab")

require("klua.table")

local signal = require("hump.signal")
local storage = require("storage")
local jnia = require("all.jni_android")
local PSU = require("platform_services_utils")
local RC = require("remote_config")
local iab = {}

iab.can_be_paused = true
iab.update_interval = 0
iab.late_update_delay = 0
iab.SRV_ID = 2
iab.SRV_DISPLAY_NAME = "Google Play"
iab.rc_suffix = "gpiab"
iab.async_purchases = true
iab.sku_index = {}
iab.purchase_history_cache = {}
iab.purchases_cache = {}
iab.products_cache = {}
iab.sync_times = {}
iab.last_cached_purchases = nil
iab.sync_purchases_in_progress = nil
iab.purchase_in_progress = nil

local REQ_ERR_IAP_PURCHASE_PENDING = 22

iab.signal_handlers = {}

function iab:init(name, params)
	if self.inited then
		log.debug("service %s already inited", name)
	else
		if not RC.v["products_" .. self.rc_suffix] then
			log.error("products_%s not defined in remote_config", self.rc_suffix)

			return nil
		end

		if not params or not params.pubkey then
			log.error("platform_services_gpiab requires pubkey param")

			return nil
		end

		self.pubkey = params.pubkey

		jnia.set_service_param("gpiab_pubkey", self.pubkey)

		do
			local result = jnia.init_service(self.SRV_ID)

			if result ~= 1 then
				log.error("platform_services_gpiab java init failed")

				return nil
			end
		end

		self:update_sku_index()

		self.prq = PSU:new_prq()

		for sn, fn in pairs(self.signal_handlers) do
			signal.register(sn, fn)
		end

		self.inited = true
	end

	if not self.names then
		self.names = {}
	end

	if not table.contains(self.names, name) then
		table.insert(self.names, name)
	end

	self.premium = true

	return true
end

function iab:shutdown(name)
	if self.inited then
		for sn, fn in pairs(self.signal_handlers) do
			signal.remove(sn, fn)
		end
	end

	self.names = nil
	self.inited = nil
end

function iab:update_sku_index()
	for _, n in pairs(RC.v["products_" .. self.rc_suffix]) do
		local p = self:get_product(n)
		local sku = p and p.skus and (p.skus[self.rc_suffix] or p.skus.default)

		if sku then
			self.sku_index[sku] = n
		end
	end
end

function iab:parse_purchases(str)
	if not str or str == "" then
		return {}
	end

	local lines = string.split(str, "\n")

	if not lines or #lines == 0 then
		return {}
	end

	local out = {}

	for _, line in pairs(lines) do
		local sku, token, signature, ackd, order_id, receipt = unpack(string.split(line, ";"))
		local id = self.sku_index[sku]

		if not id then
			log.debug("sku:%s not found in sku_index", sku)
		else
			local t = {
				sku = sku,
				token = token,
				signature = signature,
				ackd = ackd == "true",
				order_id = order_id,
				receipt = receipt
			}

			t.id = id

			table.insert(out, t)
		end
	end

	return out
end

function iab:parse_products(str)
	if not str or str == "" then
		return {}
	end

	local lines = string.split(str, "\n")

	if not lines or #lines == 0 then
		return {}
	end

	local out = {}

	for _, line in pairs(lines) do
		local sku, title, description, price, price_micros, price_currency_code = unpack(string.split(line, ";"))
		local id = self.sku_index[sku]

		if not id then
			log.debug("sku:%s not found in sku_index", sku)
		else
			local t = {
				sku = sku,
				title = title,
				description = description,
				price = price,
				price_micros = tonumber(price_micros),
				price_currency_code = price_currency_code
			}

			t.id = id

			table.insert(out, t)
		end
	end

	return out
end

function iab:deliver_purchase(id)
	log.info("delivering purchase for id: %s", id)

	local p = self:get_product(id, true)

	if not p then
		log.error("id:%s not found in remote_config", id)

		return false
	end

	if not self.purchases_cache[id] then
		self.purchases_cache[id] = {}
	end

	local cp = self.purchases_cache[id]

	if p.includes then
		for _, subid in pairs(p.includes) do
			log.debug("  delivering product pack:%s item:%s", id, subid)
			self:deliver_purchase(subid)
		end

		cp.owned = true
	elseif p.gems then
		local slot = storage:load_slot()

		if slot then
			slot.gems = slot.gems + p.reward

			if not slot.gems_purchased then
				slot.gems_purchased = 0
			end

			slot.gems_purchased = slot.gems_purchased + p.reward

			storage:save_slot(slot, nil, true)
		end
	elseif p.includes_consumables then
		local slot = storage:load_slot()

		if slot then
			for _, v in pairs(p.includes_consumables) do
				if string.find(v.name, "item_") then
					local item_id = string.gsub(v.name, "item_", "")

					if slot.items.status[item_id] and v.count then
						slot.items.status[item_id] = slot.items.status[item_id] + v.count
					else
						log.error("id:%s item not found in slot", v.item)
					end
				elseif string.find(v.name, "gems_") then
					local g = self:get_product(v.name, true)

					if g and g.gems then
						slot.gems = slot.gems + g.reward

						if not slot.gems_purchased then
							slot.gems_purchased = 0
						end

						slot.gems_purchased = slot.gems_purchased + g.reward
					else
						log.error("id:%s gempack not found in remote_config", v.name)
					end
				end
			end

			storage:save_slot(slot, nil, true)
		end
	else
		cp.owned = true
	end

	return true
end

function iab:get_container_dlc(id)
	local dlcs = self:get_dlcs()

	for _, v in pairs(dlcs) do
		local p = self:get_product(v)

		if p and p.includes and table.contains(p.includes, id) then
			return p
		end
	end
end

function iab:get_status()
	local result = jnia.get_service_status(self.SRV_ID)

	log.paranoid("get_status jni result: %s", result)

	if result == 1 then
		return true
	else
		return nil
	end
end

function iab:is_premium()
    return true
end

function iab:is_premium_valid()
    return true
end

function iab:get_sync_status()
	return self.sync_times
end

function iab:get_pending_requests()
	return self.prq
end

function iab:get_request_status(rid)
	local result = jnia.get_request_status(rid)

	log.paranoid("get_request_status (%s) jni result: %s", rid, result)

	return result
end

function iab:cancel_request(rid)
	if not rid then
		return
	end

	self.prq:remove(rid)
	jnia.delete_request(rid)
end

function iab:restore_purchases()
	self:sync_purchases()
end

function iab:sync_purchases(silent)
    local global = storage:load_global()

    for _, id in pairs(global.purchased_heroes or {}) do
        self:deliver_purchase(id)
    end
    for _, id in pairs(global.purchased_towers or {}) do
        self:deliver_purchase(id)
    end
    for _, id in pairs(global.purchased_dlcs or {}) do
        self:deliver_purchase(id)
    end

    self.sync_times.purchases = os.time()
    signal.emit(SGN_PS_SYNC_PURCHASES_FINISHED, "iap", true)
    
    self.sync_purchases_in_progress = nil
    return nil
end

function iab:sync_purchase_history()
	local function cb_sync_purchase_history(status, req)
		if not self.prq:contains(req.id) then
			return
		end

		if status == 0 then
			local history_str = jnia.get_cached_purchase_history(self.SRV_ID)

			log.debug("purchase_history string: %s", history_str)

			self.purchase_history_cache = self:parse_purchases(history_str)
			self.sync_times.purchase_history = os.time()
		end

		signal.emit(SGN_PS_SYNC_PURCHASE_HISTORY_FINISHED, "iap", status == 0, self.purchase_history_cache)
	end

	log.info("sync purchase history")

	local rid = jnia.create_request_query_purchase_history(self.SRV_ID)

	if rid < 0 then
		log.error("error syncing purchase history")

		return nil
	else
		local req = self.prq:add(rid, "sync_purchase_history", cb_sync_purchase_history)

		return rid
	end
end

function iab:purchase_product(id)
    self.fake_pending_purchase = id
    
    return 999
end

function iab:get_product(id, reference)
	if not id then
		log.error("trying to get product with nil id")

		return nil
	end

	local k = "product_" .. id
	local p = RC.v[k]

	if not p then
		log.error("product %s not found in remote_config %s", id, k)

		return nil
	end

	if reference then
		return p
	end

	local o = table.deepclone(p)

	if self.products_cache[id] then
		o = table.merge(o, self.products_cache[id])
	end

	if self.purchases_cache[id] then
		o = table.merge(o, self.purchases_cache[id])
	end

	o.id = id

	return o
end

function iab:get_offers()
	if self:is_premium() then
		log.debug("gpiab is premium. no offers shown")

		return {}
	end

	local offers = RC.v["offers_" .. self.rc_suffix]

	if not offers then
		log.error("offers_gpiab not found in remote_config")

		return {}
	end

	return offers
end

function iab:get_hero_sales()
	if self:is_premium() then
		log.debug("gpiab is premium. no hero sales shown")

		return {}
	end

	local offers = RC.v["hero_sales_" .. self.rc_suffix]

	if not offers then
		log.error("hero_sales_gpiab not found in remote_config")

		return {}
	end

	return offers
end

function iab:get_tower_sales()
	if self:is_premium() then
		log.debug("gpiab is premium. no tower sales shown")

		return {}
	end

	local offers = RC.v["tower_sales_" .. self.rc_suffix]

	if not offers then
		log.error("tower_sales_gpiab not found in remote_config")

		return {}
	end

	return offers
end

function iab:get_gems_sales()
	if self:is_premium() then
		log.error("gpiab is premium. no gems sales shown")

		return {}
	end

	local offers = RC.v["gems_sales_" .. self.rc_suffix]

	if not offers then
		log.error("TEST IAP gems_sales_%s not found in remote_config", self.rc_suffix)

		return {}
	end

	return offers
end

function iab:get_dlcs(owned)
	local dlcs = {}
	local premium = self:is_premium()

	for _, n in pairs(RC.v["products_" .. self.rc_suffix]) do
		if string.starts(n, "dlc_") then
			if owned then
				local p = self:get_product(n)

				if p and (p.owned or premium) then
					table.insert(dlcs, n)
				end
			else
				table.insert(dlcs, n)
			end
		end
	end

	return dlcs
end

function iab:get_formatted_currency(amount_micros, currency_code)
	log.debug("get_formatted_currency(%s,%s)", amount_micros, currency_code)

	return jnia.get_formatted_currency(amount_micros, currency_code)
end

function iab:sync_products()
    local products_to_sync = RC.v["products_" .. self.rc_suffix]
    
    for _, id in pairs(products_to_sync) do
        if not self.products_cache[id] then
            self.products_cache[id] = {}
        end

        local cp = self.products_cache[id]
        
        cp.sku = id
        cp.title = id
        cp.description = "Offline Unlocked"
        cp.price = "Free"
        cp.price_micros = 0
        cp.price_currency_code = "USD"
    end

    self.sync_times.products = os.time()
    signal.emit(SGN_PS_SYNC_PRODUCTS_FINISHED, "iap", true)

    return nil
end

function iab:late_update(dt)
    if self.fake_pending_purchase then
        local id = self.fake_pending_purchase
        self.fake_pending_purchase = nil

        self:deliver_purchase(id)

        local ph = {}
        local pt = {}
        local pd = {}

        for cid, _ in pairs(self.purchases_cache) do
            if string.starts(cid, "hero_") then
                table.insert(ph, cid)
            elseif string.starts(cid, "tower_") then
                table.insert(pt, cid)
            elseif string.starts(cid, "dlc_") then
                table.insert(pd, cid)
            end
        end

        local global = storage:load_global()
        global.purchased_heroes = ph
        global.purchased_towers = pt
        global.purchased_dlcs = pd
        storage:save_global(global)

        signal.emit(SGN_PS_PURCHASE_PRODUCT_FINISHED, "iap", true, id)
    end
end

return iab
