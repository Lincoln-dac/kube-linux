local flowGray = require("flow_gray")
local reqUri = ngx.var.uri
local grayPaths = {
    ["/send/"] = 6,     
    ["/pick/"] = 6,      
    ["/commerce/"] = 10  
}
local isGrayPath = false
for path, len in pairs(grayPaths) do
    if string.sub(reqUri, 1, len) == path then
        isGrayPath = true
        break  
    end
end
if isGrayPath and math.random(100) <= 10 then

    local ok, err = pcall(flowGray.setHeaders)
    if not ok then
        ngx.log(ngx.ERR, "flowGray.setHeaders failed: ", err)
    end
    ngx.var.backend = "open-edi-gray-sit2-https"
    ngx.var.customhost = "open-edi-sit2-gray.test.com"
end
