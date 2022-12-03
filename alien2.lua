local curBlankId = 0

local function cwd()
    local thisFile = debug.getinfo(1).source:sub(2)
    return thisFile:gsub("^(.+\\)[^\\]+$", "%1")
end

local function lapStringToMs(lapString)
    
    local timeComponents = lapString:gsub("%.", ":"):split(":")

    for i = 1, 3 do
        if (tonumber(timeComponents[i], 10) == nil) then
            return nil
        end
    end

    return timeComponents[3] + timeComponents[2] * 1000 + timeComponents[1] * 60 * 1000
end

local function getNextBlankId()
    curBlankId = curBlankId + 1
    return string.rep(" ", curBlankId)
end

local alien2 = ffi.load(cwd() .. "alien2.dll")

ffi.cdef[[
    void lj_disablePitLimiter(bool active);
    void lj_overrideLapTime(int time);
    void lj_setGripMultiplier(float multiplier);
    double lj_setNoclip(bool active);
    double lj_getGearRatio(int gear);
    void lj_setGearRatio(int gear, double ratio);
    void lj_resetGearRatios();
]]

local settings = {

    handling = {
        optimalTireTemp = false,
        gripMultiplier = 1.0,
        downforceAdd = 0.0,
    },

    power = {
        passiveExtra = 0.0,
        nos = 0.0,
        brake = 0.0,
        injectNosStart = -1,
        injectNosBoosting = false
    },

    drivetrain = {
        gearRatios = {}
    },

    autopilot = {
        enabled = false,
        skill = 75,
        aggressiveness = 50
    },

    lap = {
        fuelFreeze = -1,
        shouldOverride = false,
        lapTimeString = ""
    },

    misc = {
        disablePitLimiter = false,
        disableDamage = false,
        noclip = false
    },

    jays_preMade = {
        legit = false,
        fast = false,
        extreme = false,
        lights_flash = false
    }
}

local localCar;
local ratiozera = alien2.lj_getGearRatio(1);
local sound_nos_start = ac.AudioEvent.fromFile({ filename = cwd() .. "nos_engage.wav", use3D = true, loop = false }, true)
local sound_nos_loop = ac.AudioEvent.fromFile({ filename = cwd() .. "nos_loop.wav", use3D = true, loop = true }, true)

function script.windowMain(dt)
    ui.tabBar("main_tabs", function()
        ui.tabItem("Vehicle Setup", function()
            ui.text("Power Configs")
            local currentPassive, hasChangedPassive = ui.slider(getNextBlankId(), settings.power.passiveExtra, 0, 100, "%.1f - Power")
            if hasChangedPassive then
                settings.power.passiveExtra = currentPassive               
            end

            local currentBrake, hasChangedBrake = ui.slider(getNextBlankId(), settings.power.brake, 0, 100, "%.1f - Braking")
            if hasChangedBrake then
                settings.power.brake = currentBrake
            end
          
            local currentNoS, hasChangedNoS = ui.slider(getNextBlankId(), settings.power.nos, 0, 100, "%.1f - NOS Power")
            if hasChangedNoS then
                settings.power.nos = currentNoS
            end

            ui.text("Handling Configs")
            local currentGrip, hasChangedGrip = ui.slider(getNextBlankId(), settings.handling.gripMultiplier, 0, 5, "%.2fx - Grip multiplier")
            if hasChangedGrip then
                settings.handling.gripMultiplier = currentGrip
                alien2.lj_setGripMultiplier(currentGrip)
            end

            local currentDownforce, hasChangedDownforce = ui.slider(getNextBlankId(), settings.handling.downforceAdd, 0, 3000, "%.0fkg - Downforce add")
            if hasChangedDownforce then
                settings.handling.downforceAdd = currentDownforce 
            end

            if ui.checkbox("Optimal tire temperatures", settings.handling.optimalTireTemp) then
                settings.handling.optimalTireTemp = not settings.handling.optimalTireTemp
            end

        end)

        ui.tabItem("Drivetrain", function()
            for gear = 0, localCar.gearCount do
                local gearName = gear == 0 and "R" or gear
                settings.drivetrain.gearRatios[gear] = alien2.lj_getGearRatio(gear)

                local currentGearRatio, hasChangedGearRatio = ui.slider(getNextBlankId(), settings.drivetrain.gearRatios[gear], -5, 8, "%.4f - Gear: "..gearName, 2)
                if hasChangedGearRatio then

                    alien2.lj_setGearRatio(gear, currentGearRatio)
                end   
            end
            if ui.button("Reset") then
                alien2.lj_resetGearRatios()
            end
        end)

        ui.tabItem("Auto-pilot", function()
            
            ui.text("Auto pilot settings")
            local currentSkill, hasChangedSkill = ui.slider(getNextBlankId(), settings.autopilot.skill, 0, 100, "Skill - %.0f%% ")
            if hasChangedSkill then
                settings.autopilot.skill = currentSkill
                physics.setAILevel(0, currentSkill / 100)
            end

            local currentAggressiveness, hasChangedAggressiveness = ui.slider(getNextBlankId(), settings.autopilot.aggressiveness, 0, 100, "Aggressiveness - %.0f%%")
            if hasChangedAggressiveness then
                settings.autopilot.aggressiveness = currentAggressiveness
                physics.setAIAggression(0, currentAggressiveness / 100)
            end

            if ui.checkbox("Enabled", settings.autopilot.enabled) then
                settings.autopilot.enabled = not settings.autopilot.enabled
                physics.setCarAutopilot(settings.autopilot.enabled)
            end
        end)

        ui.tabItem("Misc", function()      
            if ui.checkbox("Disable pit speed limiter", settings.misc.disablePitLimiter) then
                settings.misc.disablePitLimiter = not settings.misc.disablePitLimiter
                alien2.lj_disablePitLimiter(settings.misc.disablePitLimiter)
            end

            if ui.checkbox("Disable body and engine damage", settings.misc.disableDamage) then
                settings.misc.disableDamage = not settings.misc.disableDamage
            end

            if ui.checkbox("No collisions", settings.misc.noclip) then
                settings.misc.noclip = not settings.misc.noclip
                alien2.lj_setNoclip(settings.misc.noclip)
                
            end       
            if ui.checkbox("Freeze fuel amount", settings.lap.fuelFreeze >= 0) then
                settings.lap.fuelFreeze = settings.lap.fuelFreeze > 0 and -1 or localCar.fuel
                
            end        
            local hasEnabledOverride = false
            if ui.checkbox("Override lap time", settings.lap.shouldOverride) then
                settings.lap.shouldOverride = not settings.lap.shouldOverride

                if settings.lap.shouldOverride then
                    settings.lap.lapTimeString = ac.lapTimeToString(localCar.lapTimeMs)
                    hasEnabledOverride = true
                else
                    alien2.lj_overrideLapTime(0)
                end

            end
            if settings.lap.shouldOverride then
                local currentTime, hasChangedTime = ui.inputText(" ", settings.lap.lapTimeString)
                if hasChangedTime or hasEnabledOverride then
                    settings.lap.lapTimeString = currentTime
                    local overrideLapMs = lapStringToMs(currentTime)

                    if overrideLapMs ~= nil then
                        alien2.lj_overrideLapTime(overrideLapMs)
                    end
                end

            end
            ui.text("* Laps will never be invalid with Alien V2 running")
        end)

        ui.tabItem("Mode", function()   

            if ui.checkbox("Legit Mode", settings.jays_preMade.legit) then                                                   --------------LEGIT MODE------------
                if settings.jays_preMade.fast then
                    settings.jays_preMade.fast = not settings.jays_preMade.fast
                end
                if settings.jays_preMade.extreme then
                    settings.jays_preMade.extreme = not settings.jays_preMade.extreme
                end
                settings.jays_preMade.legit = not settings.jays_preMade.legit
                if not settings.handling.optimalTireTemp then
                    settings.handling.optimalTireTemp = true
                end
                currentPassive = 0.0
                currentBrake = 2.5
                currentNoS = 0.9
                currentDownforce = 26.0
                currentGrip = 1.10
                if getNextBlankId() ~= currentPassive then
                    settings.power.passiveExtra = currentPassive
                end
                settings.power.brake = currentBrake
                settings.power.nos = currentNoS

                if getNextBlankId() ~= currentDownforce then
                    settings.handling.downforceAdd = currentDownforce
                end

                if getNextBlankId() ~= currentGrip then
                    settings.handling.gripMultiplier = currentGrip
                    alien2.lj_setGripMultiplier(currentGrip)
                end
            end
 
            if ui.checkbox("Fast", settings.jays_preMade.fast) then                                           ---------------------FAST MODE-------------------------------                                              
                if settings.jays_preMade.legit then
                    settings.jays_preMade.legit = not settings.jays_preMade.legit
                end
                if settings.jays_preMade.extreme then
                    settings.jays_preMade.extreme = not settings.jays_preMade.extreme
                end
                settings.jays_preMade.fast = not settings.jays_preMade.fast
                if not settings.handling.optimalTireTemp then
                    settings.handling.optimalTireTemp = true
                end
                currentPassive = 1.5
                currentBrake = 60.0
                currentNoS = 10.0
                currentDownforce = 26.0
                currentGrip = 1.30 
                if getNextBlankId() ~= currentPassive then
                    settings.power.passiveExtra = currentPassive
                end
                settings.power.brake = currentBrake
                settings.power.nos = currentNoS

                if getNextBlankId() ~= currentDownforce then
                    settings.handling.downforceAdd = currentDownforce
                end

                if getNextBlankId() ~= currentGrip then
                    settings.handling.gripMultiplier = currentGrip
                    alien2.lj_setGripMultiplier(currentGrip)
                end
            end

            if ui.checkbox("Extreme (Obvious)", settings.jays_preMade.extreme) then                       ------------------------------EXTREME MODE------------------------------------               
                if settings.jays_preMade.fast then
                    settings.jays_preMade.fast = not settings.jays_preMade.fast
                end
                if settings.jays_preMade.legit then
                    settings.jays_preMade.legit = not settings.jays_preMade.legit
                end
                settings.jays_preMade.extreme = not settings.jays_preMade.extreme
                if not settings.handling.optimalTireTemp then
                    settings.handling.optimalTireTemp = true
                end
                currentPassive = 200.0
                currentBrake = 200.0
                currentNoS = 100.0
                currentDownforce = 8000.0
                currentGrip = 9.00
                if getNextBlankId() ~= currentPassive then
                    settings.power.passiveExtra = currentPassive
                end
                settings.power.brake = currentBrake
                settings.power.nos = currentNoS

                if getNextBlankId() ~= currentDownforce then
                    settings.handling.downforceAdd = currentDownforce
                end

                if getNextBlankId() ~= currentGrip then
                    settings.handling.gripMultiplier = currentGrip
                    alien2.lj_setGripMultiplier(currentGrip)
                end
            end

            if ui.button("Reset to 0") then
                if settings.jays_preMade.legit then
                    settings.jays_preMade.legit = not settings.jays_preMade.legit
                end
                if settings.jays_preMade.extreme then
                    settings.jays_preMade.extreme = not settings.jays_preMade.extreme
                end
                if settings.jays_preMade.legit then
                    settings.jays_preMade.legit = not settings.jays_preMade.legit
                end
                if settings.jays_preMade.fast then
                    settings.jays_preMade.fast = not settings.jays_preMade.fast
                end
                if settings.handling.optimalTireTemp then
                    settings.handling.optimalTireTemp = false
                end
                alien2.lj_resetGearRatios()
                settings.power.passiveExtra = 0
                settings.power.brake = 0
                settings.power.nos = 0
                settings.handling.downforceAdd = 0
                settings.handling.gripMultiplier = 0
            end
        end)
    end)
end
                 

function script.update(dt)

    localCar = ac.getCar(0)

    sound_nos_start:setPosition(localCar.position, nil, nil, localCar.velocity)
    sound_nos_loop:setPosition(localCar.position, nil, nil, localCar.velocity)

    if settings.handling.optimalTireTemp then
        local temp = ac.getCar(0).wheels[0].tyreOptimumTemperature
        physics.setTyresTemperature(0, ac.Wheel.All, temp)
    end

    if settings.misc.disableDamage then
        physics.setCarBodyDamage(0, vec4(0, 0, 0, 0))
        physics.setCarEngineLife(0, 1000)
    end

    if settings.handling.downforceAdd > 0 then
        physics.addForce(0, vec3(0, 0, 0), true, vec3(0, -settings.handling.downforceAdd * 9.8 * dt * 100, 0), true)
    end
    
    if settings.power.passiveExtra > 0 and (localCar.gear > 0) and (localCar.rpm + 200 < localCar.rpmLimiter) then
        local passivePush = settings.power.passiveExtra * localCar.mass * localCar.gas * dt * 100
       
        physics.addForce(0, vec3(0, 0, 0), true, vec3(0, 0, passivePush), true)
    end

    if settings.power.brake > 0 and (localCar.speedKmh > 5) then
        local passivePush = settings.power.brake * localCar.mass * localCar.brake * dt * 100
        passivePush = localCar.localVelocity.z > 0.0 and -passivePush or passivePush
        
        physics.addForce(0, vec3(0, 0, 0), true, vec3(0, 0, passivePush), true)
    end
    
    if settings.lap.fuelFreeze >= 0 then
        physics.setCarFuel(0, settings.lap.fuelFreeze)
    end
    
    if localCar.flashingLightsActive and settings.power.nos > 0 and (localCar.gear > 0) then
        if settings.power.injectNosStart < 0 then
            settings.power.injectNosStart = ac.getSim().time
            sound_nos_start:start()
        end

        if ac.getSim().time > settings.power.injectNosStart + 700 then
            if not settings.power.injectNosBoosting then
                sound_nos_start:stop()
                sound_nos_loop:start()
                settings.power.injectNosBoosting = true
            end

            local nosPush = settings.power.nos * localCar.mass * localCar.gas * dt * 100
            physics.addForce(0, vec3(0, 0, 0), true, vec3(0, 0, nosPush), true)
            
            if ac.getSim().firstPersonCameraFOV < 75 then
                ac.setFirstPersonCameraFOV(ac.getSim().firstPersonCameraFOV + 6 * dt)
            end
        end
        
    elseif settings.power.injectNosStart > 0 then
        settings.power.injectNosStart = -1
        settings.power.injectNosBoosting = false
        sound_nos_start:stop()
        sound_nos_loop:stop()
        ac.resetFirstPersonCameraFOV()
    end

end
