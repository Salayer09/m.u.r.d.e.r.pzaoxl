-- Killer Hub - Murder Suite V10.4
-- Wall-Aware Prediction / Anti-Jukes / Ballistic Fall / Sheriff-Safe
-- Hitbox / Kill All / Silent

if getgenv().__KillerHub_MurderSuite_Loaded then
    if getgenv().KillerHub and getgenv().KillerHub.NotifyWarn then
        getgenv().KillerHub:NotifyWarn("Ya cargado", "Murder Suite ya se está ejecutando.", 3)
    end
    return
end
getgenv().__KillerHub_MurderSuite_Loaded = true

local KillerHub = loadstring(game:HttpGet("https://raw.githubusercontent.com/Salayer09/KillerHub2/main/Sheriff.lua"))()

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Camera = workspace.CurrentCamera

local MAX_DISTANCE_SQ = 1822500
local wallFilterTable = {}
local partsToCheck = {nil, nil}
local playerFysics = {}
local lastVisualPosition = Vector3.new(0, 0, 0)
local lastActualPosition = Vector3.new(0, 0, 0)
local lastTracerPosition = Vector3.new(0, 0, 0)
local cachedHasKnife = false
local lastKnifeCheck = 0
local cachedTarget = nil
local wasHitboxActive = false

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local cachedViewportSize = Camera.ViewportSize
local cachedScreenCenter = Vector2.new(cachedViewportSize.X / 2, cachedViewportSize.Y / 2)
local cachedDpiScale = 1

local function updateViewportCache()
    cachedViewportSize = Camera.ViewportSize
    cachedScreenCenter = Vector2.new(cachedViewportSize.X / 2, cachedViewportSize.Y / 2)
    local viewportY = cachedViewportSize.Y
    cachedDpiScale = viewportY > 0 and math.max(1, 1080 / viewportY) or 1
end
updateViewportCache()
KillerHub:AddTask(Camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateViewportCache))

-- Drawings
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 0.8; FOVCircle.NumSides = 36; FOVCircle.Filled = false; FOVCircle.Visible = false; FOVCircle.Transparency = 0.8
KillerHub:AddTask(FOVCircle)

local PredRingOuter = Drawing.new("Circle")
PredRingOuter.Radius = 6.0; PredRingOuter.Thickness = 1.2; PredRingOuter.Filled = false; PredRingOuter.Color = Color3.fromRGB(255, 35, 35); PredRingOuter.Visible = false
KillerHub:AddTask(PredRingOuter)

local PredDotCenter = Drawing.new("Circle")
PredDotCenter.Radius = 2.5; PredDotCenter.Thickness = 1; PredDotCenter.Filled = true; PredDotCenter.Color = Color3.fromRGB(255, 255, 255); PredDotCenter.Visible = false
KillerHub:AddTask(PredDotCenter)

local PredLine = Drawing.new("Line")
PredLine.Thickness = 1.0; PredLine.Color = Color3.fromRGB(185, 0, 255); PredLine.Transparency = 0.65; PredLine.Visible = false
KillerHub:AddTask(PredLine)

local TracerLine = Drawing.new("Line")
TracerLine.Thickness = 1.0; TracerLine.Color = Color3.fromRGB(140, 0, 255); TracerLine.Transparency = 0.9; TracerLine.Visible = false
KillerHub:AddTask(TracerLine)

local function GetFlag(flagName, default)
    local f = KillerHub.Flags[flagName]
    if f == nil or f.CurrentValue == nil then return default end
    return f.CurrentValue
end

local materialCache = {}
local function getMaterialEnum(matString)
    if materialCache[matString] then return materialCache[matString] end
    local success, mat = pcall(function() return Enum.Material[matString] end)
    local result = success and mat or Enum.Material.Plastic
    materialCache[matString] = result
    return result
end

local function hasKnifeInInventory()
    local now = os.clock()
    if now - lastKnifeCheck > 0.25 then
        lastKnifeCheck = now
        local char = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        cachedHasKnife = (char and char:FindFirstChild("Knife")) or (backpack and backpack:FindFirstChild("Knife"))
    end
    return cachedHasKnife
end

local function checkPlayerHasGun(player)
    local char = player.Character
    if char and char:FindFirstChild("Gun") then return true end
    local backpack = player:FindFirstChild("Backpack")
    return backpack and backpack:FindFirstChild("Gun") ~= nil
end

local function isVisibleThroughWalls(targetChar)
    if not targetChar then return false end
    local localChar = LocalPlayer.Character
    if not localChar then return false end

    local head = targetChar:FindFirstChild("Head")
    local torso = targetChar:FindFirstChild("UpperTorso") or targetChar:FindFirstChild("Torso")
    if not head and not torso then return false end

    local origin = Camera.CFrame.Position
    partsToCheck[1] = head
    partsToCheck[2] = torso

    for i = 1, 2 do
        local part = partsToCheck[i]
        if part then
            local direction = part.Position - origin
            if direction:Dot(direction) > 0 then
                table.clear(wallFilterTable)
                wallFilterTable[1] = localChar
                wallFilterTable[2] = targetChar
                wallFilterTable[3] = Camera

                local visible = true
                for step = 1, 3 do
                    raycastParams.FilterDescendantsInstances = wallFilterTable
                    local raycastResult = workspace:Raycast(origin, direction, raycastParams)

                    if not raycastResult then
                        visible = true
                        break
                    end

                    local hitInst = raycastResult.Instance
                    if hitInst then
                        if not hitInst.CanCollide or hitInst.Transparency >= 0.75 then
                            table.insert(wallFilterTable, hitInst)
                        else
                            visible = false
                            break
                        end
                    else
                        visible = true
                        break
                    end
                end

                if visible then return true end
            end
        end
    end

    return false
end

local CurrentSheriff = nil
local lastSheriffScan = 0

local function updateSheriffTarget()
    if CurrentSheriff and CurrentSheriff.Parent == Players then
        local char = CurrentSheriff.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 and checkPlayerHasGun(CurrentSheriff) then
            return
        end
    end

    local now = os.clock()
    if now - lastSheriffScan > 0.6 then
        lastSheriffScan = now
        CurrentSheriff = nil

        local allPlayers = Players:GetPlayers()
        for i = 1, #allPlayers do
            local player = allPlayers[i]
            if player ~= LocalPlayer and checkPlayerHasGun(player) then
                local char = player.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    CurrentSheriff = player
                    break
                end
            end
        end
    end
end

local function getClosestTargetToFOV()
    local localHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not localHrp then return nil end

    local aimType = GetFlag("KnifeAimType", "Target FOV")
    local wallCheck = GetFlag("KnifeWallCheckActive", false)
    local prioritizeSheriff = GetFlag("PrioritizeSheriffActive", false)
    local fovRadius = GetFlag("FovRadiusMurder", 150)
    local allPlayers = Players:GetPlayers()

    if aimType == "Nearest Player" then
        local nearestPlayer = nil
        local shortestDistSq = MAX_DISTANCE_SQ

        for i = 1, #allPlayers do
            local player = allPlayers[i]
            if player ~= LocalPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")

                if hrp and humanoid and humanoid.Health > 0 then
                    local diff = hrp.Position - localHrp.Position
                    local distSq = diff:Dot(diff)
                    if distSq <= shortestDistSq then
                        if wallCheck and not isVisibleThroughWalls(player.Character) then
                            continue
                        end
                        shortestDistSq = distSq
                        nearestPlayer = player
                    end
                end
            end
        end

        cachedTarget = nearestPlayer
        return nearestPlayer
    end

    if prioritizeSheriff then
        updateSheriffTarget()
    else
        CurrentSheriff = nil
    end

    if CurrentSheriff and CurrentSheriff.Character then
        local hrp = CurrentSheriff.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local diff = hrp.Position - localHrp.Position
            if diff:Dot(diff) <= MAX_DISTANCE_SQ then
                local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    local distToCenter = (Vector2.new(screenPos.X, screenPos.Y) - cachedScreenCenter).Magnitude
                    if distToCenter < fovRadius then
                        if not wallCheck or isVisibleThroughWalls(CurrentSheriff.Character) then
                            cachedTarget = CurrentSheriff
                            return CurrentSheriff
                        end
                    end
                end
            end
        end
    end

    local closestInnocent = nil
    local shortestDistance = fovRadius

    for i = 1, #allPlayers do
        local player = allPlayers[i]
        if player ~= LocalPlayer and player ~= CurrentSheriff and player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")

            if hrp and humanoid and humanoid.Health > 0 then
                local diff = hrp.Position - localHrp.Position
                if diff:Dot(diff) > MAX_DISTANCE_SQ then continue end

                local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    local distToCenter = (Vector2.new(screenPos.X, screenPos.Y) - cachedScreenCenter).Magnitude
                    if distToCenter < shortestDistance then
                        if wallCheck and not isVisibleThroughWalls(player.Character) then
                            continue
                        end
                        shortestDistance = distToCenter
                        closestInnocent = player
                    end
                end
            end
        end
    end

    cachedTarget = closestInnocent
    return closestInnocent
end

-- Knife ballistic prediction with vertical correction
local function getAdvancedKnifePrediction(targetChar)
    if not targetChar then return nil, nil end
    local hrp = targetChar:FindFirstChild("HumanoidRootPart")
    local humanoid = targetChar:FindFirstChildOfClass("Humanoid")
    local localHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

    if not hrp or not humanoid or not localHrp then return nil, nil end

    local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
    local targetPosition = hrp.Position
    local distance = (targetPosition - localHrp.Position).Magnitude
    local physicsData = playerFysics[targetPlayer]

    if physicsData and physicsData.IsLaggingOut then
        return targetPosition, targetPosition
    end

    local extentsY = targetChar:GetExtentsSize().Y
    local scaleFactor = 1.0
    if humanoid:FindFirstChild("BodyHeightScale") then scaleFactor = humanoid.BodyHeightScale.Value end

    if extentsY < 4.8 or scaleFactor < 0.85 then
        local heightDeficit = math.clamp((5.1 - extentsY) * 0.52, 0.4, 2.3)
        targetPosition = targetPosition - Vector3.new(0, heightDeficit, 0)
    end

    local smoothVelocity = physicsData and physicsData.SmoothedVelocity or Vector3.new(0, 0, 0)
    if smoothVelocity:Dot(smoothVelocity) < 0.0225 then return targetPosition, targetPosition end

    local rawPing = 0.06
    if Stats and Stats:FindFirstChild("Network") and Stats.Network:FindFirstChild("ServerToClientPing") then
        rawPing = Stats.Network.ServerToClientPing:GetValue() / 1000
    end
    local ping = math.clamp(rawPing, 0.01, 0.25)
    local travelTime = (distance / 85) + ping

    local horizontalVelocity = Vector3.new(smoothVelocity.X, 0, smoothVelocity.Z)
    local exactSpeed = horizontalVelocity.Magnitude

    local MAX_WALKSPEED = 16.715
    if exactSpeed > MAX_WALKSPEED then
        horizontalVelocity = horizontalVelocity.Unit * MAX_WALKSPEED
        exactSpeed = MAX_WALKSPEED
    end

    local jukeFactor = 1.0
    if physicsData and physicsData.LastVelocity then
        local lastHorizVel = Vector3.new(physicsData.LastVelocity.X, 0, physicsData.LastVelocity.Z)
        local lastSpeed = lastHorizVel.Magnitude

        if exactSpeed > 1 and lastSpeed > 1 then
            local currentDir = horizontalVelocity.Unit
            local lastDir = lastHorizVel.Unit
            local dotProduct = currentDir:Dot(lastDir)

            if dotProduct < 0.94 then
                jukeFactor = math.clamp(dotProduct, 0.10, 1.0)
            end

            if exactSpeed < lastSpeed * 0.85 then
                local decelerationRatio = exactSpeed / lastSpeed
                jukeFactor = jukeFactor * math.clamp(decelerationRatio, 0.05, 1.0)
            end
        end
    end

    local velocityScale = math.clamp(exactSpeed / MAX_WALKSPEED, 0, 1)
    if exactSpeed < 12 then
        velocityScale = math.pow(velocityScale, 1.4)
    end

    local shortRangeBoost = distance < 20 and 1.15 or 1.0
    local dynamicScale = (1.0 + (distance * 0.004)) * shortRangeBoost
    local maxElasticCap = math.clamp(distance * 0.38, 3.5, 13.5)

    local hPredConfig = GetFlag("KnifeHorizSlider", 145) / 1000
    local vPredConfig = GetFlag("KnifeVertSlider", 40) / 1000

    local horizontalOffset = horizontalVelocity * (hPredConfig * 6.8) * travelTime * dynamicScale * jukeFactor * velocityScale
    if horizontalOffset:Dot(horizontalOffset) > (maxElasticCap * maxElasticCap) then
        horizontalOffset = horizontalOffset.Unit * maxElasticCap
    end

    local verticalOffset = Vector3.new(0, 0, 0)
    local isAir = (humanoid.FloorMaterial == Enum.Material.Air)
    local absYVelocity = math.abs(smoothVelocity.Y)

    if isAir then
        local verticalVelocity = math.clamp(smoothVelocity.Y, -20, 25)
        local verticalDistanceScale = 1 / (1 + (distance * 0.005))

        local fallDamping = verticalVelocity < 0 and 0.32 or 0.70
        local calculatedYOffset = verticalVelocity * fallDamping * (vPredConfig * 5.8) * travelTime * verticalDistanceScale

        if calculatedYOffset < 0 then
            table.clear(wallFilterTable)
            wallFilterTable[1] = targetChar
            wallFilterTable[2] = LocalPlayer.Character
            wallFilterTable[3] = Camera
            raycastParams.FilterDescendantsInstances = wallFilterTable

            local floorRay = workspace:Raycast(targetPosition, Vector3.new(0, -30, 0), raycastParams)
            if floorRay then
                local maxPossibleDrop = math.max(0, targetPosition.Y - (floorRay.Position.Y + 2.1))
                if math.abs(calculatedYOffset) > maxPossibleDrop then
                    calculatedYOffset = -maxPossibleDrop
                end
            end
        end

        verticalOffset = Vector3.new(0, calculatedYOffset, 0)
    elseif absYVelocity > 0.02 then
        local verticalVelocity = smoothVelocity.Y
        local rampCompensationFactor = 1.20
        local sliderScale = (vPredConfig / 0.040)
        verticalOffset = Vector3.new(0, verticalVelocity * travelTime * sliderScale * rampCompensationFactor, 0)
    end

    local finalPredictedPos = targetPosition + horizontalOffset + verticalOffset

    table.clear(wallFilterTable)
    wallFilterTable[1] = targetChar
    wallFilterTable[2] = LocalPlayer.Character
    wallFilterTable[3] = Camera
    raycastParams.FilterDescendantsInstances = wallFilterTable

    local wallRay = workspace:Raycast(targetPosition, finalPredictedPos - targetPosition, raycastParams)
    if wallRay and wallRay.Instance and wallRay.Instance.CanCollide then
        local hitDistance = (wallRay.Position - targetPosition).Magnitude
        if hitDistance > 0.5 then
            finalPredictedPos = targetPosition + (finalPredictedPos - targetPosition).Unit * (hitDistance - 0.4)
        else
            finalPredictedPos = targetPosition
        end
    end

    return targetPosition, finalPredictedPos
end

-- UI
local MurderTab = KillerHub:CreateTab("Murder", "rbxassetid://104386785713574")

MurderTab:CreateSection("Knife Combats")
MurderTab:CreateToggle("KnifeAimActive", "Knife Thrown aim", function(state) end)
MurderTab:CreateDropdown("KnifeAimType", "Type of throw aim", {"Target FOV", "Nearest Player"}, function(selected) end)
MurderTab:CreateToggle("PrioritizeSheriffActive", "Prioritize Sheriff", function(state) end)
MurderTab:CreateToggle("KnifeWallCheckActive", "Wall Check", function(state) end)

MurderTab:CreateDropdown("KnifeThrowType", "Knife throwing type", {"Normal", "Fast"}, function(selected) end)
MurderTab:CreateSlider("KnifeThrowDistance", "Throw Advance Distance", 0, 100, function(value) end)

MurderTab:CreateSlider("KnifeHorizSlider", "Horizontal prediction", 0, 300, function(value) end)
MurderTab:CreateSlider("KnifeVertSlider", "Vertical prediction", 0, 120, function(value) end)

MurderTab:CreateSection("Stab Hitbox Modifier")
MurderTab:CreateToggle("StabHitboxMaster", "Stab Hitbox", function(state) end)
MurderTab:CreateToggle("SeeHitboxActive", "See hitbox", function(state) end)
MurderTab:CreateSlider("HitboxSizeSlider", "Stab Hitbox Size", 2, 30, function(value) end)
MurderTab:CreateSlider("HitboxTransparencySlider", "Hitbox transparency", 0, 100, function(value) end)

MurderTab:CreateDropdown("HitboxMaterialDropdown", "Hitbox Material",
    {"Plastic", "SmoothPlastic", "Metal", "DiamondPlate", "Glass", "Neon", "ForceField", "Wood"},
    function(selected) end
)

MurderTab:CreateSection("Visuals & Environment")
MurderTab:CreateToggle("ShowKnifePredictionVisual", "See prediction", function(state) end)
MurderTab:CreateToggle("ShowKnifeTracerVisual", "See prediction tracer", function(state) end)
MurderTab:CreateToggle("SmartHandVisibility", "Smart Visibility", function(state) end)

MurderTab:CreateSection("Modify FOV")
MurderTab:CreateToggleColorPicker("FovVisibleMurder", "FovColorMurder", "Show FOV Circle", Color3.fromRGB(0, 255, 185), function(state) end, function(color) end)
MurderTab:CreateSlider("FovRadiusMurder", "FOV Radius", 30, 600, function(value) end)

-- Heartbeat loop
local hbConn = RunService.Heartbeat:Connect(function()
    local silentAimActive = GetFlag("KnifeAimActive", false)
    local hitboxActive = GetFlag("StabHitboxMaster", false)
    local smartVis = GetFlag("SmartHandVisibility", false)
    local hasKnife = hasKnifeInInventory()

    local shouldRunAimLogic = silentAimActive and (not smartVis or hasKnife)

    if shouldRunAimLogic then
        getClosestTargetToFOV()
    else
        cachedTarget = nil
    end

    if not hitboxActive and wasHitboxActive then
        wasHitboxActive = false
        local allPlayers = Players:GetPlayers()
        for i = 1, #allPlayers do
            local player = allPlayers[i]
            if player ~= LocalPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.Size = Vector3.new(2, 2, 1)
                    hrp.Transparency = 1
                    hrp.Material = Enum.Material.Plastic
                end
            end
        end
    end

    if not shouldRunAimLogic and not hitboxActive then return end
    if hitboxActive then wasHitboxActive = true end

    local currentTime = os.clock()
    local seeHitbox = GetFlag("SeeHitboxActive", false)
    local hitboxSize = GetFlag("HitboxSizeSlider", 2)
    local transSlider = GetFlag("HitboxTransparencySlider", 0)
    local targetTransparency = math.clamp(transSlider, 0, 100) / 100
    local matEnum = getMaterialEnum(GetFlag("HitboxMaterialDropdown", "Plastic"))
    local targetSize = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
    local allPlayers = Players:GetPlayers()

    for i = 1, #allPlayers do
        local player = allPlayers[i]
        if player ~= LocalPlayer and player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")

            if hrp then
                if hitboxActive then
                    if hrp.Size ~= targetSize then hrp.Size = targetSize end
                    if hrp.CanCollide then hrp.CanCollide = false end

                    if seeHitbox then
                        if hrp.Transparency ~= targetTransparency then hrp.Transparency = targetTransparency end
                        if hrp.Material ~= matEnum then hrp.Material = matEnum end
                    else
                        if hrp.Transparency ~= 1 then hrp.Transparency = 1 end
                    end
                end

                if shouldRunAimLogic then
                    local currentPos = hrp.Position
                    local physicsVelocity = hrp.AssemblyLinearVelocity

                    if not playerFysics[player] then
                        playerFysics[player] = {
                            LastPos = currentPos,
                            LastTime = currentTime,
                            SmoothedVelocity = physicsVelocity,
                            LastVelocity = physicsVelocity,
                            LastRawVelocity = physicsVelocity,
                            ConsecutiveSameVelocity = 0,
                            IsLaggingOut = false
                        }
                    else
                        local data = playerFysics[player]
                        local deltaTime = currentTime - data.LastTime

                        if deltaTime > 0 then
                            local positionalVelocity = (currentPos - data.LastPos) / deltaTime
                            local realVelocity = Vector3.new(physicsVelocity.X, positionalVelocity.Y, physicsVelocity.Z)

                            local diffVel = realVelocity - data.LastRawVelocity
                            if data.LastRawVelocity and diffVel:Dot(diffVel) < 0.000001 then
                                data.ConsecutiveSameVelocity = data.ConsecutiveSameVelocity + 1
                            else
                                data.ConsecutiveSameVelocity = 0
                            end

                            data.LastRawVelocity = realVelocity

                            if data.ConsecutiveSameVelocity > 20 and realVelocity:Dot(realVelocity) > 1 then
                                data.IsLaggingOut = true
                                realVelocity = Vector3.new(0, 0, 0)
                            else
                                data.IsLaggingOut = false
                            end

                            if positionalVelocity:Dot(positionalVelocity) > 3025 then
                                realVelocity = Vector3.new(0, 0, 0)
                            end

                            data.LastVelocity = data.SmoothedVelocity
                            data.SmoothedVelocity = data.SmoothedVelocity:Lerp(realVelocity, 0.20)
                        end

                        data.LastPos = currentPos
                        data.LastTime = currentTime
                    end
                end
            end
        end
    end
end)
KillerHub:AddTask(hbConn)

local rsConn = RunService.RenderStepped:Connect(function()
    local silentAimActive = GetFlag("KnifeAimActive", false)

    if not silentAimActive then
        FOVCircle.Visible = false
        PredDotCenter.Visible = false
        PredRingOuter.Visible = false
        PredLine.Visible = false
        TracerLine.Visible = false
        return
    end

    local hasKnife = hasKnifeInInventory()
    local smartVis = GetFlag("SmartHandVisibility", false)

    if smartVis and not hasKnife then
        FOVCircle.Visible = false
        PredDotCenter.Visible = false
        PredRingOuter.Visible = false
        PredLine.Visible = false
        TracerLine.Visible = false
        return
    end

    local showFOV = GetFlag("FovVisibleMurder", false)
    if showFOV then
        FOVCircle.Position = cachedScreenCenter
        FOVCircle.Radius = GetFlag("FovRadiusMurder", 150) * cachedDpiScale
        FOVCircle.Thickness = 0.8 * cachedDpiScale
        FOVCircle.Color = GetFlag("FovColorMurder", Color3.fromRGB(0, 255, 185))
        FOVCircle.Visible = true
    else
        FOVCircle.Visible = false
    end

    local activeTarget = cachedTarget

    local showPred = GetFlag("ShowKnifePredictionVisual", false)
    if showPred and activeTarget and activeTarget.Character then
        local basePos, rawPredictedPos = getAdvancedKnifePrediction(activeTarget.Character)
        if basePos and rawPredictedPos then
            lastActualPosition = lastActualPosition:Lerp(basePos, 0.28)
            lastVisualPosition = lastVisualPosition:Lerp(rawPredictedPos, 0.28)

            local screenPosBase, onScreenBase = Camera:WorldToViewportPoint(lastActualPosition)
            local screenPosPred, onScreenPred = Camera:WorldToViewportPoint(lastVisualPosition)

            if onScreenBase and onScreenPred then
                local drawBase = Vector2.new(screenPosBase.X, screenPosBase.Y)
                local drawPred = Vector2.new(screenPosPred.X, screenPosPred.Y)

                PredDotCenter.Radius = 2.5 * cachedDpiScale
                PredDotCenter.Thickness = 1 * cachedDpiScale
                PredRingOuter.Radius = 6.0 * cachedDpiScale
                PredRingOuter.Thickness = 1.2 * cachedDpiScale
                PredLine.Thickness = 1.0 * cachedDpiScale

                PredDotCenter.Position = drawBase
                PredRingOuter.Position = drawPred
                PredLine.From = drawBase
                PredLine.To = drawPred

                local lineDiff = drawBase - drawPred
                PredLine.Visible = lineDiff:Dot(lineDiff) >= (2.25 * cachedDpiScale * cachedDpiScale)
                PredDotCenter.Visible = true
                PredRingOuter.Visible = true
            else
                PredDotCenter.Visible = false; PredRingOuter.Visible = false; PredLine.Visible = false
            end
        else
            PredDotCenter.Visible = false; PredRingOuter.Visible = false; PredLine.Visible = false
        end
    else
        PredDotCenter.Visible = false; PredRingOuter.Visible = false; PredLine.Visible = false
        if activeTarget and activeTarget.Character then
            local hrp = activeTarget.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                lastActualPosition = hrp.Position
                lastVisualPosition = hrp.Position
            end
        end
    end

    local showTracer = GetFlag("ShowKnifeTracerVisual", false)
    if showTracer and activeTarget and activeTarget.Character then
        local _, rawPredictedPos = getAdvancedKnifePrediction(activeTarget.Character)
        if rawPredictedPos then
            lastTracerPosition = lastTracerPosition:Lerp(rawPredictedPos, 0.80)

            local char = LocalPlayer.Character
            local rightHand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
            local originWorld = rightHand and rightHand.Position or (char and char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart.Position)

            if originWorld then
                local screenHand, onScreenHand = Camera:WorldToViewportPoint(originWorld)
                local screenPred, onScreenPred = Camera:WorldToViewportPoint(lastTracerPosition)

                if onScreenHand or onScreenPred then
                    TracerLine.From = Vector2.new(screenHand.X, screenHand.Y)
                    TracerLine.To = Vector2.new(screenPred.X, screenPred.Y)
                    TracerLine.Thickness = 1.0 * cachedDpiScale
                    TracerLine.Visible = true
                else
                    TracerLine.Visible = false
                end
            else
                TracerLine.Visible = false
            end
        else
            TracerLine.Visible = false
        end
    else
        TracerLine.Visible = false
        if activeTarget and activeTarget.Character then
            local hrp = activeTarget.Character:FindFirstChild("HumanoidRootPart")
            if hrp then lastTracerPosition = hrp.Position end
        end
    end
end)
KillerHub:AddTask(rsConn)

-- Silent aim hooks
local ClientServices = ReplicatedStorage:WaitForChild("ClientServices", 5)
if ClientServices then
    local WeaponService = require(ClientServices:WaitForChild("WeaponService"))
    local oldGetTargetPosition = WeaponService.GetTargetPosition
    local oldGetMouseTargetCFrame = WeaponService.GetMouseTargetCFrame

    WeaponService.GetTargetPosition = function(self, ...)
        local silentAim = GetFlag("KnifeAimActive", false)
        if silentAim and hasKnifeInInventory() then
            local targetPlayer = cachedTarget or getClosestTargetToFOV()
            if targetPlayer and targetPlayer.Character then
                local _, predictedPos = getAdvancedKnifePrediction(targetPlayer.Character)
                if predictedPos then return CFrame.new(predictedPos) end
            end
        end
        return oldGetTargetPosition(self, ...)
    end

    WeaponService.GetMouseTargetCFrame = function(self, ...)
        local silentAim = GetFlag("KnifeAimActive", false)
        if silentAim and hasKnifeInInventory() then
            local targetPlayer = cachedTarget or getClosestTargetToFOV()
            if targetPlayer and targetPlayer.Character then
                local _, predictedPos = getAdvancedKnifePrediction(targetPlayer.Character)
                if predictedPos then return CFrame.new(predictedPos) end
            end
        end
        return oldGetMouseTargetCFrame(self, ...)
    end
end

local rawNamecall
rawNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args = {...}

    if not checkcaller() and method == "FireServer" and self.Name == "KnifeThrown" then
        local throwType = GetFlag("KnifeThrowType", "Normal")
        local throwDistConfig = GetFlag("KnifeThrowDistance", 14)

        if throwType == "Fast" and throwDistConfig > 0 and #args >= 2 and typeof(args[1]) == "CFrame" and typeof(args[2]) == "CFrame" then
            local originCF = args[1]
            local targetCF = args[2]

            local direction = (targetCF.Position - originCF.Position)
            local dist = direction.Magnitude

            if dist > 0 then
                local lookDir = direction.Unit
                local advanceDistance = math.min(throwDistConfig, dist * 0.75)

                args[1] = originCF + (lookDir * advanceDistance)
            end

            return rawNamecall(self, unpack(args))
        end
    end

    return rawNamecall(self, ...)
end))

return KillerHub
