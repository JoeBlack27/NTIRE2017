require 'image'
local signal = require 'signal'

local M = {}

function M.frequencyDividing(sample, wc)
    local h = (sample:dim() == 3) and sample:size(2) or sample:size(1)
    local w = (sample:dim() == 3) and sample:size(2) or sample:size(1)
    local hwc = math.ceil(wc * h / 2)
    local wwc = math.ceil(wc * w / 2)
    local filter = torch.ones(h, w)
    filter[{{hwc, h - hwc + 1}, {}}] = 0
    filter[{{}, {wwc, w - wwc + 1}}] = 0

    local divide(img, wc)
        local Fi = signal.fft2(img)
        local Flow = torch.cmul(Fi, filter)
        local Fhigh = Fi - Flow

        return {
            signal.ifft2(Flow):narrow(3, 1, 1):squeeze(),
            signal.ifft2(Fhigh):narrow(3, 1, 1):squeeze()
            }
    end

    if (sample:dim() == 3) then
        if (sample:size(1) == 1) then
            return divide(sample[1], wc)
        elseif (sample:size(1) == 3) then
            local ret = {torch.Tensor(sample:size()), torch.Tensor(sample:size())}
            for i = 1, 3 do
                local divideChannel = divide(sample[i], wc)
                ret[1][i] = divideChannel[1]
                ret[2][i] = divideChannel[2]
            end
            return ret
        end
    else
        return divide(sample, wc)
    end
    return {}
end

function M.Compose(transforms)
   return function(sample)
      for _, transform in ipairs(transforms) do
         sample = transform(sample)
      end
      return sample
   end
end

function M.HorizontalFlip(prob)
   return function(sample)
      if torch.uniform() < prob then
         sample.input = image.hflip(sample.input)
         sample.target = image.hflip(sample.target)
      end
      return sample
   end
end

function M.Rotation(prob)
    return function(sample)
        if torch.uniform() < prob then
            local theta = torch.random(0,3)
            sample.input = image.rotate(sample.input, theta * math.pi/2)
            sample.target = image.rotate(sample.target, theta * math.pi/2)
            return sample
        end
    end
end

-- Lighting noise (AlexNet-style PCA-based noise)
function M.Lighting(alphastd, eigval, eigvec)
   return function(sample)
      if alphastd == 0 then
         return sample
      end

      local alpha = torch.Tensor(3):normal(0, alphastd)
      local rgb = eigvec:clone()
         :cmul(alpha:view(1, 3):expand(3, 3))
         :cmul(eigval:view(1, 3):expand(3, 3))
         :sum(2)
         :squeeze()

      sample.input = sample.input:clone()
      sample.target = sample.target:clone()
      for i=1,3 do
         sample.input[i]:add(rgb[i])
         sample.target[i]:add(rgb[i])
      end
      return sample 
   end
end

local function blend(img1, img2, alpha)
   return img1:mul(alpha):add(1 - alpha, img2)
end

local function grayscale(dst, img)
   dst:resizeAs(img)
   dst[1]:zero()
   dst[1]:add(0.299, img[1]):add(0.587, img[2]):add(0.114, img[3])
   dst[2]:copy(dst[1])
   dst[3]:copy(dst[1])
   return dst
end

function M.Saturation(var)
   local gs

   return function(sample)
      gs = gs or sample.input.new()
      grayscale(gs, sample.input)

      local alpha = 1.0 + torch.uniform(-var, var)
      blend(sample.input, gs, alpha)

      gs = sample.target.new()
      grayscale(gs, sample.target)
      blend(sample.target, gs, alpha)

      return sample
   end
end

function M.Brightness(var)
   local gs

   return function(sample)
      gs = gs or sample.input.new()
      gs:resizeAs(sample.input):zero()

      local alpha = 1.0 + torch.uniform(-var, var)
      blend(sample.input, gs, alpha)

      gs = sample.target.new()
      gs:resizeAs(sample.target):zero()
      blend(sample.target, gs, alpha)

      return sample
   end
end

function M.Contrast(var)
   local gs

   return function(sample)
      gs = gs or sample.input.new()
      grayscale(gs, sample.input)
      gs:fill(gs[1]:mean())

      local alpha = 1.0 + torch.uniform(-var, var)
      blend(sample.input, gs, alpha)

      gs = sample.target.new()
      grayscale(gs, sample.target)
      gs:fill(gs[1]:mean())
      blend(sample.target, gs, alpha)

      return sample
   end
end

function M.RandomOrder(ts)
   return function(sample)
      local order = torch.randperm(#ts)
      for i=1,#ts do
        sample = ts[order[i]](sample)
      end
      return sample
   end
end

function M.ColorJitter(opt)
   local brightness = opt.brightness or 0
   local contrast = opt.contrast or 0
   local saturation = opt.saturation or 0

   local ts = {}
   if brightness ~= 0 then
      table.insert(ts, M.Brightness(brightness))
   end
   if contrast ~= 0 then
      table.insert(ts, M.Contrast(contrast))
   end
   if saturation ~= 0 then
      table.insert(ts, M.Saturation(saturation))
   end

   if #ts == 0 then
      return function(sample) return sample end
   end

   return M.RandomOrder(ts)
end

return M
