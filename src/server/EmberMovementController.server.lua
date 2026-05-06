local modules = script.Parent:WaitForChild("modules")
local EmberMovementService = require(modules:WaitForChild("EmberMovementService"))

EmberMovementService.start()
