-- UIAnimationHelper
-- Purpose: Reusable animation utilities for UI elements
-- Provides: Numeric counters, color pulses, bounce effects, smooth transitions

local TweenService = game:GetService("TweenService")

local UIAnimationHelper = {}

-- =============================================================================
-- Numeric Counter Animation
-- =============================================================================
-- Smoothly animates a number display from current to target value
-- Usage: UIAnimationHelper.animateNumber(textLabel, 0, 1000, 1.5)

function UIAnimationHelper.animateNumber(textLabel, fromValue, toValue, duration)
	if not textLabel or not duration or duration <= 0 then
		return
	end

	local currentValue = fromValue
	local increment = (toValue - fromValue) / (duration * 60) -- Assuming 60 FPS

	local startTime = tick()
	local connection = nil

	connection = game:GetService("RunService").Heartbeat:Connect(function()
		local elapsed = tick() - startTime

		if elapsed >= duration then
			textLabel.Text = tostring(math.floor(toValue))
			connection:Disconnect()
			return
		end

		currentValue = fromValue + (toValue - fromValue) * (elapsed / duration)
		textLabel.Text = tostring(math.floor(currentValue))
	end)

	return connection
end

-- =============================================================================
-- Color Pulse Animation
-- =============================================================================
-- Pulses a UI element's color or text color
-- Usage: UIAnimationHelper.pulseColor(textLabel, Color3.new(1,1,1), 0.4, 2)

function UIAnimationHelper.pulseColor(element, targetColor, duration, repetitions)
	if not element then
		return
	end

	repetitions = repetitions or 1
	local isTextElement = element:IsA("TextLabel") or element:IsA("TextButton")
	local originalColor = isTextElement and element.TextColor3 or element.ImageColor3

	for i = 1, repetitions do
		local pulseOut = TweenInfo.new(duration / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local pulseIn = TweenInfo.new(duration / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		if isTextElement then
			local tween1 = TweenService:Create(element, pulseOut, { TextColor3 = targetColor })
			local tween2 = TweenService:Create(element, pulseIn, { TextColor3 = originalColor })

			tween1:Play()
			tween1.Completed:Wait()
			if i < repetitions then
				tween2:Play()
				tween2.Completed:Wait()
			end
		else
			local tween1 = TweenService:Create(element, pulseOut, { ImageColor3 = targetColor })
			local tween2 = TweenService:Create(element, pulseIn, { ImageColor3 = originalColor })

			tween1:Play()
			tween1.Completed:Wait()
			if i < repetitions then
				tween2:Play()
				tween2.Completed:Wait()
			end
		end
	end
end

-- =============================================================================
-- Bounce Effect (Scale)
-- =============================================================================
-- Animates a bounce effect by scaling element up then down
-- Usage: UIAnimationHelper.bounce(frame, 1.15, 0.3)

function UIAnimationHelper.bounce(element, scaleAmount, duration)
	if not element then
		return
	end

	local originalScale = element.Size

	local bounceUp = TweenInfo.new(duration / 3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local bounceDown = TweenInfo.new(duration * 2 / 3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local scaledSize = UDim2.new(
		originalScale.X.Scale * scaleAmount,
		originalScale.X.Offset,
		originalScale.Y.Scale * scaleAmount,
		originalScale.Y.Offset
	)

	local tween1 = TweenService:Create(element, bounceUp, { Size = scaledSize })
	local tween2 = TweenService:Create(element, bounceDown, { Size = originalScale })

	tween1:Play()
	tween1.Completed:Connect(function()
		tween2:Play()
	end)
end

-- =============================================================================
-- Fade Transition (Generic)
-- =============================================================================
-- Fades between two states with smooth easing
-- Usage: UIAnimationHelper.fadeTransition(element, 0, 1, 0.3, "TextTransparency")

function UIAnimationHelper.fadeTransition(element, fromValue, toValue, duration, property)
	if not element or not property then
		return
	end

	property = property or "ImageTransparency"

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(element, tweenInfo, { [property] = toValue })

	element[property] = fromValue
	tween:Play()

	return tween
end

-- =============================================================================
-- Glow Effect (Brightness oscillation)
-- =============================================================================
-- Creates a glowing effect through repeated scaling and rotation
-- Usage: UIAnimationHelper.glowEffect(frame, 0.5)

function UIAnimationHelper.glowEffect(element, intensity, duration)
	if not element then
		return
	end

	intensity = intensity or 0.3
	duration = duration or 1.0

	local connection = nil
	local startTime = tick()

	connection = game:GetService("RunService").Heartbeat:Connect(function()
		local elapsed = (tick() - startTime) % duration
		local progress = elapsed / duration
		local glow = 1 + math.sin(progress * math.pi * 2) * intensity

		element.ImageColor3 = Color3.new(glow, glow, glow)
	end)

	return connection
end

-- =============================================================================
-- Slide Transition
-- =============================================================================
-- Smoothly slides an element from one position to another
-- Usage: UIAnimationHelper.slideTransition(frame, UDim2.new(...), 0.4)

function UIAnimationHelper.slideTransition(element, targetPosition, duration, easingStyle)
	if not element then
		return
	end

	easingStyle = easingStyle or Enum.EasingStyle.Quad
	local tweenInfo = TweenInfo.new(duration, easingStyle, Enum.EasingDirection.Out)
	local tween = TweenService:Create(element, tweenInfo, { Position = targetPosition })

	tween:Play()

	return tween
end

-- =============================================================================
-- Shake Effect (Subtle screen shake)
-- =============================================================================
-- Creates a subtle shake animation for emphasis
-- Usage: UIAnimationHelper.shake(frame, 10, 0.2) -- 10 pixels, 0.2 seconds

function UIAnimationHelper.shake(element, intensity, duration)
	if not element then
		return
	end

	intensity = intensity or 5
	duration = duration or 0.3
	local originalPosition = element.Position

	local startTime = tick()
	local connection = nil

	connection = game:GetService("RunService").Heartbeat:Connect(function()
		local elapsed = tick() - startTime

		if elapsed >= duration then
			element.Position = originalPosition
			connection:Disconnect()
			return
		end

		local shakeX = math.sin(elapsed * 25) * intensity
		local shakeY = math.cos(elapsed * 20) * intensity

		element.Position = originalPosition + UDim2.new(0, shakeX, 0, shakeY)
	end)

	return connection
end

return UIAnimationHelper
