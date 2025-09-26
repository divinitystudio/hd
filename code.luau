local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
 
local GunSystem = require(script.Parent.GunSystem)
local GunStats = require(ReplicatedStorage.Information.GunStats)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Ragdoll = require(script.Parent.Ragdoll)
 
local Bots = {}
 
function Bots.Spawn(position: Vector3, gunName: string, team: string, botName)
    local gunModel = ReplicatedStorage.Models.GunModels:FindFirstChild(gunName) --checking if it exists
    if not gunModel then
        warn(`Could not find gun model: {gunName}`) --so i know why it failed
        return
    end
 
    local bot = ServerStorage.Bots[botName]:Clone()
    local hrp: BasePart = bot.HumanoidRootPart
    local humanoid = bot.Humanoid
 
    hrp.CFrame = CFrame.new(position + Vector3.new(0, 5, 0)) --putting it 5 above so it doesnt glitch into the floor
 
    for _, v in bot:GetChildren() do
        if not v:IsA("BasePart") then --if it isnt of class basepart we skip into the next loop cycle
            continue
        end
 
        v.CollisionGroup = `{team}Player` --collision group to let teams go trough team specific doors
    end
 
    Ragdoll.SetupCharacter(bot)
 
    bot.Parent = workspace[`{team}Team`]
 
    for _, v in bot:GetDescendants() do
        pcall(function() --pcalling to make sure it doesnt error (if setnetworkowner isnt a member of v or if v is anchored or wtv)
            v:SetNetworkOwner(nil)
        end)
    end
 
    gunModel = gunModel:Clone()
 
    local isDual = if gunModel:FindFirstChild("Gun1") and gunModel:FindFirstChild("Gun2") then true else false
 
    --the reason im not using Welds or WeldConstraints but using m6ds here is so the gun can move in the animations
    if isDual then
        local m6d = Instance.new("Motor6D")
        m6d.Part0 = bot.RightHand
        m6d.Part1 = gunModel.Gun1.PrimaryPart
        m6d.C1 = gunModel.HoldCF.Value
        m6d.Parent = gunModel
 
        local m6d2 = Instance.new("Motor6D")
        m6d2.Part0 = bot.LeftHand
        m6d2.Part1 = gunModel.Gun2.PrimaryPart
        m6d2.C1 = gunModel.HoldCF.Value
        m6d2.Parent = gunModel
    else
        local m6d = Instance.new("Motor6D")
        m6d.Part0 = bot.RightHand
        m6d.Part1 = gunModel.PrimaryPart
        m6d.C1 = gunModel.HoldCF.Value
        m6d.Parent = gunModel
    end
 
    gunModel.Parent = bot --parenting it last so its less glitchy and could save performance
 
    local idleGunAnim = humanoid.Animator:LoadAnimation(gunModel.Animations.Idle)
    idleGunAnim:Play()
    local walkAnim = humanoid.Animator:LoadAnimation(ReplicatedStorage.Animations.Run)
    local idleAnim = humanoid.Animator:LoadAnimation(bot.Animate.idle.Animation1)
    idleAnim:Play()
 
    local path = PathfindingService:CreatePath({ AgentRadius = 3 }) --agent radius to make sure bots dont get stuck on walls
    local destinations = workspace.Map[team].BotPositions:GetChildren()
    local destination = destinations[math.random(1, #destinations)].Position
 
    local destinationThread
    local moveThread
 
    local function goToDestination()
        local succes, errorMessage = pcall(function() --compute async can fail
            path:ComputeAsync(hrp.Position, destination)
        end)
 
        if succes and path.Status == Enum.PathStatus.Success then
            if moveThread then --if were already moving then we cancel the current move thread
                task.cancel(moveThread)
            end
 
            local waypoints = path:GetWaypoints()
 
            for i = 2, #waypoints do --starting from 2nd waypoint since 1st is same as the bots position
                if i >= #waypoints + 1 then --if we reached the end we set the walktopoint to hrp pos so the walktopoint effectively                                            --resets
                    humanoid.WalkToPoint = hrp.Position
                    break
                end
 
                local waypoint = waypoints[i]
 
                --using WalkToPoint instead of humanoid:MoveTo since moveTo is incredibly janky and laggy
                humanoid.WalkToPoint = hrp.Position + (waypoint.Position - hrp.Position).Unit * 100
 
                if waypoint.Action == Enum.PathWaypointAction.Jump then
                    humanoid.Jump = true --make the bot jump
                end
 
                repeat
                    task.wait()
                until vector.magnitude( --using vector.magnitude instead of Vector3.Magnitude since its faster
                        Vector3.new(hrp.Position.X, waypoint.Position.Y, hrp.Position.Z) - waypoint.Position
                    ) < 6
            end
        else
            warn(errorMessage)
        end
    end
 
    destinationThread = task.defer(goToDestination) --defer instead of spawn since we dont need it immediately
 
    local target
 
    local animThread = task.defer(function()
        while task.wait() do
            --cant do Humanoid.MoveDirection since were using WalkToPoint to move the bot
            local isMoving = hrp.AssemblyLinearVelocity.X ~= 0 and hrp.AssemblyLinearVelocity.Z ~= 0
 
            local killThread
 
            if target and killThread then
                task.cancel(killThread)
            end
 
            if isMoving then
                if killThread then
                    task.cancel(killThread)
                end
                idleAnim:Stop()
                if not walkAnim.IsPlaying then
                    walkAnim:Play()
                end
            else
                killThread = task.delay(15, function() --if bot hasnt moved for 15 seconds then its probably its stuck on a wall so                                                        --we kill it
                    if target then
                        return
                    end
                    humanoid.Health = 0
                end)
                walkAnim:Stop()
                if not idleAnim.IsPlaying then
                    idleAnim:Play()
                end
            end
        end
    end)
 
    local function move()
        local actions = { "Follow", "Move" }
        local enemyHRP = target.HumanoidRootPart
 
        while true do
            local action = actions[math.random(1, #actions)]
 
             --named actions so its more readable
            if action == "Follow" then
                bot.Humanoid.WalkToPoint = enemyHRP.Position
            elseif action == "Move" then
                bot.Humanoid.WalkToPoint = hrp.Position
                    + Vector3.new(
                        if math.random(1, 2) == 1 then -1 else 1 * math.random(0, 20) / 10,
                        0,
                        if math.random(1, 2) == 1 then -1 else 1 * math.random(0, 20) / 10
                    )
            end
 
            task.wait(math.random(20, 50) / 10) --math.random(2, 5) would just return values: 2,3,4,5, math.random(20, 50) / 10 will                                                 --return values: 2, 2.6, 4.2, ...
            if not bot or not bot:IsDescendantOf(workspace) or not bot:FindFirstChild("Humanoid") then
                break --the bot variable wont be nil even if the bot has been destroyed so we check if its a descendant of workspace                        --as well and the bot also could exist but not have any children so we check for humanoid
            end
            bot.Humanoid.WalkToPoint = hrp.Position
        end
    end
 
    local startedTarget = 0
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = { bot, workspace.Effects } --stuff we dont want our raycast to hit
 
    local searchThread = task.defer(function()
        while task.wait(0.7) do
            for _, enemy in if team == "Red" then workspace.BlueTeam:GetChildren() else workspace.RedTeam:GetChildren() do
                local enemyHRP = enemy:FindFirstChild("HumanoidRootPart")
                if not enemyHRP then
                    continue
                end
 
                local distance = vector.magnitude(hrp.Position - enemyHRP.Position)
                if distance > 200 then
                    continue
                end
 
                --we need the head later so if it doesnt exist then we break out of the loop (end the loop)
                if not bot:FindFirstChild("Head") then
                    break
                end
 
                local raycast = workspace:Raycast(
                    bot.Head.Position,
                    (enemyHRP.Position - bot.Head.Position).Unit * 200,
                    raycastParams
                )
 
                if not raycast or not raycast.Instance then
                    continue
                end
 
                if not raycast.Instance:IsDescendantOf(enemy) then
                    continue
                end
 
                if enemy.Humanoid.Health <= 0 then
                    continue
                end
 
                target = enemy
 
                startedTarget = os.clock() --later used to calculate bot accuracy
                moveThread = task.defer(move)
                task.cancel(destinationThread)
                humanoid.WalkToPoint = hrp.Position
                break
            end
        end
    end)
 
    local function lostTarget()
        target = nil
        destinationThread = task.defer(goToDestination)
    end
 
    local shootThread = task.defer(function()
        while task.wait() do
            if not target then
                continue
            end
 
            if
                not target:IsDescendantOf(workspace)
                or not target:FindFirstChild("Humanoid")
                or not bot:FindFirstChild("Head")
            then
                target = nil
                continue
            end
 
            local enemyHRP = target.HumanoidRootPart
            local raycast =
                workspace:Raycast(bot.Head.Position, (enemyHRP.Position - bot.Head.Position).Unit * 200, raycastParams)
 
            if not raycast or not raycast.Instance then
                lostTarget()
                continue
            end
            if not raycast.Instance:IsDescendantOf(target) then
                lostTarget()
                continue
            end
            if target.Humanoid.Health <= 0 then
                lostTarget()
                continue
            end
 
            local accuracy = os.clock() - startedTarget
 
            local endPos = raycast.Position
            local asv = enemyHRP.AssemblyLinearVelocity --get the movement velocity of the enemy so we can predict shots
            local direction = if asv == Vector3.zero then Vector3.zero else asv.Unit
            endPos += direction * 5
            endPos += Vector3.new(
                math.random(10, 20) / if math.random(1, 2) == 2 then -10 else 10, --randomizing between -1, -2 and 1, 2
                math.random(10, 20) / if math.random(1, 2) == 2 then -10 else 10,
                math.random(10, 20) / if math.random(1, 2) == 2 then -10 else 10
            ) / (accuracy * 2.2)
            local bulletId = math.random(1, 65000) --this doesnt have to be a giant number and we dont need to check if the bullet id
                                                    --we generated exists since its just a bullet and it doesnt matter
            GunSystem.BotShoot(bulletId, gunModel, endPos)
 
            task.wait(60 / GunStats[gunName].FireRate) --fireRate is in RPM
        end
    end)
 
    local diedSignal = Signal.new() --have to use signal to avoid cyclic dependency
 
    humanoid.Died:Once(function()
        task.cancel(shootThread)
        task.cancel(searchThread)
        task.cancel(animThread)
        if destinationThread then
            task.cancel(destinationThread)
        end
        if moveThread then
            task.cancel(moveThread)
        end
 
        gunModel:Destroy()
 
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None --disabling name and health display on humanoid
 
        Ragdoll.Ragdoll(bot)
 
        diedSignal:Fire()
    end)
 
    return diedSignal
end
 
return Bots
