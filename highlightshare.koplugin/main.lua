
local Dispatcher = require("dispatcher")  -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local http = require("socket.http")  
local ltn12 = require("ltn12")  
local socketutil = require("socketutil")  
local rapidjson = require("rapidjson")
local socket = require("socket")
local _ = require("gettext")

local worker_url = "https://kindle-relay.kindle-relay.workers.dev/quote"

local HighlightShare = WidgetContainer:extend{
    name = "highlightshare",
    is_doc_only = false,
}

function HighlightShare:init()
     -- Load settings with defaults  
    self.settings = G_reader_settings:readSetting("highlightshare", {})

    -- Register with menu system  
    self.ui.menu:registerToMainMenu(self) 

    self.ui.highlight:addToHighlightDialog("13_sendAndHighlight", function(this)  
        return {  
            text = _("Highlight and Send to Discord"),  
            enabled = this.hold_pos ~= nil, -- optional condition  
            callback = function()
                HighlightShare:send(self)
                this:saveHighlight(true)
                this:onClose() -- close dialog after action  
            end  
        }  
    end)

    self.ui.highlight:addToHighlightDialog("14_sendToDiscord", function(this)  
        return {  
            text = _("Send to Discord"),  
            enabled = this.hold_pos ~= nil, -- optional condition  
            callback = function()
                HighlightShare:send(self)
                this:onClose() -- close dialog after action  
            end  
        }  
    end)
end

function HighlightShare:send(self)
    if not self.settings.token then 
        UIManager:show(InfoMessage:new{  
        text = "Set a password to send to discord",  
        timeout = 3 
        })
    else 
        local highlight = HighlightShare:getSelectedHighlight(self)
        local code, parsed_response = HighlightShare:sendHighlightToDiscord(self, highlight)
        local data = nil
        local ok = false

        if parsed_response and parsed_response ~= "" then
            ok, data = pcall(rapidjson.decode, parsed_response)
        end

        if code == 200 then
            UIManager:show(InfoMessage:new{
                text = "Success!",
                timeout = 3
            })
        elseif data and data.error == "expiredToken" then
            UIManager:show(InfoMessage:new{
                text = "Token expired! Please give bot /refresh command to be issued a new token.",
            })
        else
            UIManager:show(InfoMessage:new{
                text = "Something went wrong. Make sure your token is entered correctly!",
                timeout = 3
            })
        end
    end
end

function HighlightShare:getSelectedHighlight(self)
    local current_selection = self.ui.highlight.selected_text

    -- Get book metadata 
    local doc_props = self.ui.doc_props  
    local book_title = doc_props.display_title or doc_props.title  
    local book_author = doc_props.authors 

    -- Get page numbers  
    local current_page  
    if self.ui.rolling then  
        current_page = self.document:getPageFromXPointer(current_selection.pos0)  
    else  
        current_page = current_selection.pos0.page  
    end 

    local metadata = {  
        text = current_selection.text,  
        title = book_title,  
        author = book_author,  
        page = current_page,
        token = self.settings.token
    }

    return metadata
end

function HighlightShare:sendHighlightToDiscord(self, highlight_metadata)
    -- Set timeout  
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)  
  
    -- Prepare request data  
    local body_json = rapidjson.encode(highlight_metadata)  

    -- Create request  
    local response_body = {}
    local request = {  
        url = worker_url,  
        method = "POST",  
        headers = {  
            ["Content-Type"] = "application/json",  
            ["Content-Length"] = #body_json
        },  
        source = ltn12.source.string(body_json),  
        sink = ltn12.sink.table(response_body)  
    }
    -- Execute request  
    local code, headers, status = socket.skip(1, http.request(request))
    local parsed_response = table.concat(response_body)

    socketutil:reset_timeout()

    return code, parsed_response
end

function HighlightShare:addToMainMenu(menu_items)  
    menu_items.highlightshare = {  
        text = _("Highlight Share Token"),  
        sorting_hint = "tools",  
        callback = function()  
            self:showAccountSettings()  
        end,  
    }  
end

function HighlightShare:showAccountSettings()
    local dialog
    dialog = InputDialog:new{  
        title = _("Enter token provided by bot below"),  
        input = self.settings.token or "",  
        input_hint = _("Enter the token from the Discord bot"),  
        text_type = "password",  
        buttons = {  
            {  
                {  
                    text = _("Cancel"),  
                    id = "close",  
                    callback = function()  
                        UIManager:close(dialog)  
                    end,  
                },  
                {  
                    text = _("Save"),  
                    is_enter_default = true,  
                    enabled_func = function()  
                        return dialog:getInputText() ~= ""  
                    end,  
                    callback = function()  
                        self.settings.token = dialog:getInputText()  
                        G_reader_settings:saveSetting("highlightshare", self.settings)  
                        UIManager:close(dialog)  
                        UIManager:show(Notification:new{  
                            text = _("Settings saved"),  
                            timeout = 2,  
                        })  
                    end,  
                },  
            }  
        },  
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end


return HighlightShare