-- starts driving the course
function courseplay:start(self)
	self.maxnumber = table.getn(self.Waypoints)
	if self.maxnumber < 1 then
		return
	end
	
	--Manual ignition v3.01/3.04 (self-installing)
	if self.setManualIgnitionMode ~= nil and self.ignitionMode ~= nil and self.ignitionMode ~= 2 then
		self:setManualIgnitionMode(2);
		
	--Manual ignition v3.x (in steerable as lua)
	elseif self.ignitionKey ~= nil and self.allowedIgnition ~= nil and not self.isMotorStarted then
		self.ignitionKey = true;
        self.allowedIgnition = true;
    end;
    --END manual ignition
	
	if self.cp.orgRpm == nil then
		self.cp.orgRpm = {}
		self.cp.orgRpm[1] = self.motor.maxRpm[1]
		self.cp.orgRpm[2] = self.motor.maxRpm[2]
		self.cp.orgRpm[3] = self.motor.maxRpm[3]
	end
	if self.ESLimiter ~= nil and self.ESLimiter.maxRPM[5] ~= nil then
		self.cp.ESL = {}
		self.cp.ESL[1] = self.ESLimiter.percentage[2]
		self.cp.ESL[2] = self.ESLimiter.percentage[3]
		self.cp.ESL[3] = self.ESLimiter.percentage[4]
	end

	self.CPnumCollidingVehicles = 0;
	self.traffic_vehicle_in_front = nil
	--self.numToolsCollidingVehicles = {};
	self.drive = false
	self.record = false
	self.record_pause = false
	self.calculated_course = false

	AITractor.addCollisionTrigger(self, self);

	self.orig_maxnumber = self.maxnumber
	-- set default ai_state if not in mode 2 or 3
	if self.ai_mode ~= 2 and self.ai_mode ~= 3 then
		self.ai_state = 0
	end

	--TODO: section needed?
	if (self.ai_mode == 4 or self.ai_mode == 6) and self.tipper_attached then
		local start_anim_time = self.tippers[1].startAnimTime
		if start_anim_time == 1 then
			self.fold_move_direction = 1
		else
			self.fold_move_direction = -1
		end
	end

	if self.recordnumber < 1 then
		self.recordnumber = 1
	end

	-- add do working players if not already added
	if self.working_course_player_num == nil then
		self.working_course_player_num = courseplay:add_working_player(self)
	end
	self.cp.backMarkerOffset = nil
	self.cp.aiFrontMarker = nil

	courseplay:reset_tools(self)
	-- show arrow
	self.dcheck = true
	-- current position
	local ctx, cty, ctz = getWorldTranslation(self.rootNode);
	-- position of next waypoint
	local cx, cz = self.Waypoints[self.recordnumber].cx, self.Waypoints[self.recordnumber].cz
	-- distance
	local dist = courseplay:distance(ctx, ctz, cx, cz)
	

	for k,workTool in pairs(self.tippers) do    --TODO temporary solution (better would be Tool:getIsAnimationPlaying(animationName))
		if courseplay:isFolding(workTool) then
			if  self.setAIImplementsMoveDown ~= nil then
				self:setAIImplementsMoveDown(true)
			elseif self.setFoldState ~= nil then
				self:setFoldState(-1, true)
			end
		end
	end

	if self.ai_state == 0 then
		local nearestpoint = dist
		local numWaitPoints = 0
		self.cp.waitPoints = {};
		self.cp.shovelFillStartPoint = nil
		self.cp.shovelFillEndPoint = nil
		self.cp.shovelEmptyPoint = nil
		local recordNumber = 0
		-- search nearest Waypoint
		for i = 1, self.maxnumber do
			local cx, cz = self.Waypoints[i].cx, self.Waypoints[i].cz
			local wait = self.Waypoints[i].wait
			dist = courseplay:distance(ctx, ctz, cx, cz)
			if dist <= nearestpoint then
				nearestpoint = dist
				recordNumber = i
			end
			-- specific Workzone
			if self.ai_mode == 4 or self.ai_mode == 6 or self.ai_mode == 7 then
				if wait then
					numWaitPoints = numWaitPoints + 1
					self.cp.waitPoints[numWaitPoints] = i;
				end

				if numWaitPoints == 1 and (self.startWork == nil or self.startWork == 0) then
					self.startWork = i
				end
				if numWaitPoints > 1 and (self.stopWork == nil or self.stopWork == 0) then
					self.stopWork = i
				end

			--unloading point for transporter
			elseif self.ai_mode == 8 then
				if wait then
					numWaitPoints = numWaitPoints + 1;
					self.cp.waitPoints[numWaitPoints] = i;
				end;

			--work points for shovel
			elseif self.ai_mode == 9 then
				if wait then
					numWaitPoints = numWaitPoints + 1;
					self.cp.waitPoints[numWaitPoints] = i;
				end;
				
				if numWaitPoints == 1 and self.cp.shovelFillStartPoint == nil then
					self.cp.shovelFillStartPoint = i;
				end;
				if numWaitPoints == 2 and self.cp.shovelFillEndPoint == nil then
					self.cp.shovelFillEndPoint = i;
				end;
				if numWaitPoints == 3 and self.cp.shovelEmptyPoint == nil then
					self.cp.shovelEmptyPoint = i;
				end;
			end;
		end;
		local changed = false
		for i=recordNumber,recordNumber+3 do
			if self.Waypoints[i]~= nil and self.Waypoints[i].turn ~= nil then
				self.recordnumber = i + 2
				changed = true
				break
			end	
		end
		if changed == false then
			self.recordnumber = recordNumber
		end

		-- mode 6 without start and stop point, set them at start and end, for only-on-field-courses
		if (self.ai_mode == 4 or self.ai_mode == 6) then
			if numWaitPoints == 0 or self.startWork == nil then
				self.startWork = 1;
			end;
			if numWaitPoints == 0 or self.stopWork == nil then
				self.stopWork = self.maxnumber;
			end;
		end
		if self.recordnumber > self.maxnumber then
			self.recordnumber = 1
		end

		self.cp.numWaitPoints = numWaitPoints;
	end --END if ai_state == 0

	if self.recordnumber > 2 and self.ai_mode ~= 4 and self.ai_mode ~= 6 then
		self.loaded = true
	elseif self.ai_mode == 4 or self.ai_mode == 6 then
		self.loaded = false;
		self.cp.hasUnloadingRefillingCourse = self.maxnumber > self.stopWork + 7;
		courseplay:debug(string.format("%s: maxnumber=%d, stopWork=%d, hasUnloadingRefillingCourse=%s", nameNum(self), self.maxnumber, self.stopWork, tostring(self.cp.hasUnloadingRefillingCourse)), 12);
	end

	if self.ai_mode == 9 or self.cp.startAtFirstPoint then
		self.recordnumber = 1;
		self.cp.shovelState = 1;
	end;

	courseplay:updateAllTriggers();

	self.forceIsActive = true;
	self.stopMotorOnLeave = false;
	self.steeringEnabled = false;
	self.deactivateOnLeave = false
	self.disableCharacterOnLeave = false
	-- ok i am near the waypoint, let's go
	self.checkSpeedLimit = false
	self.runOnceStartCourse = true;
	self.drive = true;
	self.cp.maxFieldSpeed = 0
	self.record = false
	self.dcheck = false
	
	if self.isRealistic then
		self.cp.savedTransmissionMode = self.realTransmissionMode.currentMode
		self.cpSavedRealAWDModeOn = self.realAWDModeOn
		
	end

	--EifokLiquidManure
	self.cp.EifokLiquidManure.searchMapHoseRefStation.pull = true;
	self.cp.EifokLiquidManure.searchMapHoseRefStation.push = true;

	courseplay:validateCanSwitchMode(self);
end

-- stops driving the course
function courseplay:stop(self)
	--self:dismiss()
	self.forceIsActive = false;
	self.stopMotorOnLeave = true;
	self.steeringEnabled = true;
	self.deactivateOnLeave = true
	self.disableCharacterOnLeave = true
	if self.cp.orgRpm then
		self.motor.maxRpm[1] = self.cp.orgRpm[1]
		self.motor.maxRpm[2] = self.cp.orgRpm[2]
		self.motor.maxRpm[3] = self.cp.orgRpm[3]
	end
	if self.ESLimiter ~= nil and self.ESLimiter.maxRPM[5] ~= nil then
		self.ESLimiter.percentage[2] =	self.cp.ESL[1]
		self.ESLimiter.percentage[3] =	self.cp.ESL[2]
		self.ESLimiter.percentage[4] =	self.cp.ESL[3]  
	end
	self.forced_to_stop = false
	self.record = false
	self.record_pause = false
	if self.ai_state > 4 then
		self.ai_state = 1
	end
	self.cp.turnStage = 0
	self.cp.isTurning = nil
	self.aiTractorTargetX = nil
	self.aiTractorTargetZ = nil
	self.aiTractorTargetBeforeTurnX = nil
	self.aiTractorTargetBeforeTurnZ = nil
	self.cp.backMarkerOffset = nil
	self.cp.aiFrontMarker = nil
	self.cp.aiTurnNoBackward = false
	self.cp.noStopOnEdge = false
	if self.isRealistic then
		self.motor.speedLevel = 0 
		self:realSetAwdActive(self.cpSavedRealAWDModeOn)
		for i = 1,3 do
			if self.realTransmissionMode.currentMode ~= self.cp.savedTransmissionMode  then
				self:realSetNextTransmissionMode();
			end
		end
	end
	self.cp.fillTrigger = nil
	AITractor.removeCollisionTrigger(self, self);


	--deactivate beacon lights
	if self.beaconLightsActive then
		self:setBeaconLightsVisibility(false);
	end;

	--open all covers
	if self.tipper_attached and self.cp.tipperHasCover and self.ai_mode == 1 or self.ai_mode == 2 or self.ai_mode == 5 or self.ai_mode == 6 then
		courseplay:openCloseCover(self, nil, false);
	end;

	-- resetting variables
	courseplay:setMinHudPage(self, nil);
	self.cp.attachedCombineIdx = nil;
	self.cp.tempCollis = {}
	self.checkSpeedLimit = true
	self.cp.currentTipTrigger = nil
	self.drive = false
	self.play = true
	self.dcheck = false
	self.cp.numWaitPoints = 0;
	self.cp.waitPoints = {};

	self.motor:setSpeedLevel(0, false);
	self.motor.maxRpmOverride = nil;
	self.startWork = nil
	self.stopWork = nil
	self.cp.hasUnloadingRefillingCourse = false;
	self.StopEnd = false
	self.unloaded = false
	
	self.cp.hasBaleLoader = false;
	self.cp.hasSowingMachine = false;
	if self.cp.tempWpOffsetX ~= nil then
		self.WpOffsetX = self.cp.tempWpOffsetX
		self.cp.tempWpOffsetX = nil
	end

	--reset EifokLiquidManure
	courseplay.thirdParty.EifokLiquidManure.resetData(self);

	--validation: can switch ai_mode?
	courseplay:validateCanSwitchMode(self);
end