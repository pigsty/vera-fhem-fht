-- Vera Plugin for FHEM/FHT thermostat
--
-- Heavily based on Hugh Evans MiOS Plugin for Radio Thermostat Corporation of America, Inc. Wi-Fi Thermostats (Copyright 2012)
--
-- Modifications for FHEM/FHT Copyright 2013 Chris Birkinshaw
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.


-- Load required modules

local luup = luup
local string = string
local require = require
local math = math
local http = require("socket.http")
local json = require("json")
local log = require("L_FHEM_FHT_log")

-- Define SIDs used by the various thermostat services

local TEMP_SENSOR_SID = "urn:upnp-org:serviceId:TemperatureSensor1"
local HEAT_SETPOINT_SID = "urn:upnp-org:serviceId:TemperatureSetpoint1_Heat"
local FAN_MODE_SID = "urn:upnp-org:serviceId:HVAC_FanOperatingMode1"
local USER_OPERATING_MODE_SID = "urn:upnp-org:serviceId:HVAC_UserOperatingMode1"
local MCV_HA_DEVICE_SID = "urn:micasaverde-com:serviceId:HaDevice1"
local MCV_OPERATING_STATE_SID = "urn:micasaverde-com:serviceId:HVAC_OperatingState1"

-- Set up some constants

local DEFAULT_POLL_INTERVAL = 60
local DEFAULT_NUM_RETRIES = 10

-- Variables

local g_ipPort = "8083"
local g_nextPollTime = 0
local g_deviceId = nil
local g_ipAddress = nil

--------------------------------
------- Local Functions --------
--------------------------------

--- Send a request to to a URL with optional requestParameters that will be JSON encoded.
-- Expects a JSON formatted response that will be decoded into a Lua table
-- @return response - a table of the decoded JSON response, or nil if failed
local function doHttpRequest(url, requestParameters)
	local postData = nil
	local response = nil

	if (requestParameters ~= nil) then
		log.debug ("requestParameters = " , requestParameters)
		postData = json.encode (requestParameters)
	end

	log.debug("Making HTTP request: ", "url = ",url, ", postData = ",postData)
	local body, status, headers = http.request(url, postData)

	if (body == nil or status == nil or headers == nil or status ~= 200) then
		log.error ("Received bad HTTP response")
		log.error ("URL: " ,url)
		log.error ("postData: ",postData)
		log.error ("Status: ",status)
		log.error ("Body: " ,body)
		log.error ("Headers: ",headers)
	else
		log.debug ("Received good HTTP response")
		log.debug ("URL: " ,url)
		log.debug ("postData: ",postData)
		log.debug ("Status: ",status)
		log.debug ("Body: " ,body)
		log.debug ("Headers: ",headers)
		response = json.decode(body)
		log.debug ("Parsed response: ",response)
	end

	return response
end

--- Call the thermostat API using the given path and request parameters.
-- Will retry communications upon failure, unless noRetry is set to true.
-- @parameter path
-- @parameter requestParameters
-- @parameter noRetry
-- @return response - the JSON response decoded into a Lua table, or nil if failed
local function callThermostatAPI(path, noRetry)
	log.info("Calling thermostat API, path = ",path,", noRetry = ", noRetry)
	local retries = 0
	local numRetries = DEFAULT_NUM_RETRIES

	if (noRetry) then
		numRetries = 0
	end

	repeat
		-- if this is a retry, then we wait a little
		luup.sleep(retries * 500)
		if (retries > 0) then
			log.info("retrying request, path = ", path, ", retry #", retries)
		end

		local response = doHttpRequest ("http://" .. g_ipAddress .. ":" .. g_ipPort .. path)
		if (not response) then
			log.error ("Received no response (timeout?), path = ", path)
		else
			log.info ("Received succesful response, path = ", path, ", response = ", response)
			return (response)
		end

		retries = retries + 1
	until (retries > numRetries)

	return (nil)
end

--- Retrieve the current status from the thermostat, and store in the appropriate luup variabes.
local function retrieveThermostatStatus()

	local response = callThermostatAPI("/fhem?cmd=jsonlist+" .. g_remoteId .. "&XHR=1")

	local actuator = (response["ResultSet"]["Results"]["READINGS"]["actuator"]["VAL"]) or ""
	local desiredTemp = (response["ResultSet"]["Results"]["READINGS"]["desired-temp"]["VAL"]) or ""
	local measuredTemp = (response["ResultSet"]["Results"]["READINGS"]["measured-temp"]["VAL"]) or ""

	-- FHEM does not provide the mode status so the below line does not work
	--local mode = (response["ResultSet"]["Results"]["READINGS"]["mode"]["VAL"]) or ""

	luup.variable_set(HEAT_SETPOINT_SID, "CurrentSetpoint", desiredTemp, g_deviceId)
	luup.variable_set(TEMP_SENSOR_SID, "CurrentTemperature",  measuredTemp, g_deviceId)


	-- Not working as FHEM does not report mode status

--	if mode == "Holiday_Short" or mode == "Holiday_Long" then
--		local modeStatus = "Off"
--	elseif mode == "Auto" or mode == "Manual" then  
--		local modeStatus = "HeatOn"
--	else
--		log.error("Thermostat returned invalid Mode")
--	end

--	luup.variable_set(USER_OPERATING_MODE_SID, "ModeStatus", modeStatus, g_deviceId)


	-- ModeState should be Heating or Idle (from MCV spec) but FHT reports % actuator value

	if actuator == "0%" then
		local fanStatus = "Off"
		local modeState = "Idle"
	else
		local fanStatus = "On"
		local modeState = "Heating"
	end

	luup.variable_set(FAN_MODE_SID, "FanStatus", fanStatus, g_deviceId)
	luup.variable_set(MCV_OPERATING_STATE_SID, "ModeState", modeState, g_deviceId)

	luup.variable_set(MCV_HA_DEVICE_SID, "LastUpdate", os.time(), g_deviceId)

	return true
end



--------------------------------------------
---------- GLOBAL FUNCTIONS ----------------
--------------------------------------------


-- main "polling" function to update and monitor the thermostat settings
function thermostatPoller(pollAgain)

	log.info ("Polling device " , g_deviceId, ", pollAgain = ", pollAgain)

	local currentTime = os.time()

	-- To allow change in poll time if we have called the API
	if (currentTime < g_nextPollTime and pollAgain and pollAgain == "true") then
		log.info ("Too early for next poll attempt for device " , g_deviceId)
		luup.call_delay("thermostatPoller", g_nextPollTime - currentTime, "true", true)
		return
	end

	retrieveThermostatStatus()

	if (pollAgain and pollAgain == "true") then
		luup.call_delay("thermostatPoller", DEFAULT_POLL_INTERVAL, "true", true)
	end

	log.debug ("Exiting thermostatPoller")
end

-- Start the pugin and get status from the API
function thermostatInitialize(lul_device)
	log.info("Starting initialization")
	g_deviceId = tonumber(lul_device)
	g_ipAddress = luup.devices[g_deviceId].ip
	g_remoteId = luup.devices[g_deviceId].id

	if (g_ipAddress and g_ipAddress ~= "") then
	    log.info("Using IP Address: " , g_ipAddress)
	else
	    local msg = "No IP Address configured for thermostat"
	    log.error(msg)
	    return false, msg, "FHEM/FHT Thermostat"
	end

	retrieveThermostatStatus()

	-- start the polling loop after the user specified delay
	luup.call_delay("thermostatPoller", DEFAULT_POLL_INTERVAL, "true", true)

	log.info("Done with initialization")
end

function updateSetpoint(value)
	log.info("New setpoint value = ",value)

	local success = nil
	luup.variable_set(HEAT_SETPOINT_SID, "CurrentSetpoint", value, g_deviceId)

	local path = "/fhem?cmd=set%20" .. g_remoteId .. "%20desired-temp%20" .. value
	success = callThermostatAPI(path)

	if (success) then
		log.debug("succesfully updated thermostat")
	end

	luup.variable_set(MCV_HA_DEVICE_SID, "LastUpdate", os.time(), g_deviceId)

	return true
end


-- RETURN GLOBAL FUNCTIONS
return {
	thermostatInitialize=thermostatInitialize,
	thermostatPoller=thermostatPoller,
	updateSetpoint=updateSetpoint
}

