function gmid_gui()
% GMID_GUI MATLAB GUI: 从工艺模型文件自动生成/绘制 gm/Id 曲线
% 
% 设计目标：
% 1) 读取常见 SPICE/BSIM 模型文件（.lib/.scs/.mdl/.sp）中的关键参数；
% 2) 基于 EKV 近似模型自动生成 gm/Id 曲线；
% 3) 支持 NMOS/PMOS 切换、温度修正、可视化关键点；
% 4) 支持将曲线导出为 CSV。
%
% 说明：
% - 实际 PDK 细节高度依赖 foundry 与仿真器，模型参数命名并不统一；
% - 本工具使用“可解析参数 + EKV近似”路线，适合前期尺寸估算；
% - tapeout 前请使用正式仿真器（Spectre/HSPICE 等）进行最终验证。

    app = struct();
    app.fig = uifigure('Name','GM/ID Curve Generator','Position',[100 100 1200 720]);

    app.grid = uigridlayout(app.fig,[1 2]);
    app.grid.ColumnWidth = {350, '1x'};

    % ---------------- Left Panel: Controls ----------------
    left = uipanel(app.grid,'Title','Control Panel');
    left.Layout.Row = 1; left.Layout.Column = 1;
    lgrid = uigridlayout(left,[17 2]);
    lgrid.RowHeight = repmat({28},1,17);
    lgrid.ColumnWidth = {120,'1x'};

    uilabel(lgrid,'Text','Model File');
    app.edFile = uieditfield(lgrid,'text','Value','');
    uibutton(lgrid,'Text','Browse...','ButtonPushedFcn',@onBrowse,'Layout',struct('Row',2,'Column',1));
    app.lblFileStatus = uilabel(lgrid,'Text','No file loaded','Layout',struct('Row',2,'Column',2));

    uilabel(lgrid,'Text','Device Type','Layout',struct('Row',3,'Column',1));
    app.ddType = uidropdown(lgrid,'Items',{'NMOS','PMOS'},'Value','NMOS','Layout',struct('Row',3,'Column',2));

    uilabel(lgrid,'Text','Model Name(Optional)','Layout',struct('Row',4,'Column',1));
    app.edModelName = uieditfield(lgrid,'text','Value','','Layout',struct('Row',4,'Column',2));

    uilabel(lgrid,'Text','L (um)','Layout',struct('Row',5,'Column',1));
    app.edL = uieditfield(lgrid,'numeric','Value',0.18,'Limits',[0.01 10],'Layout',struct('Row',5,'Column',2));

    uilabel(lgrid,'Text','W (um)','Layout',struct('Row',6,'Column',1));
    app.edW = uieditfield(lgrid,'numeric','Value',1.0,'Limits',[0.01 1e4],'Layout',struct('Row',6,'Column',2));

    uilabel(lgrid,'Text','Temp (°C)','Layout',struct('Row',7,'Column',1));
    app.edTemp = uieditfield(lgrid,'numeric','Value',27,'Limits',[-40 175],'Layout',struct('Row',7,'Column',2));

    uilabel(lgrid,'Text','IC Min','Layout',struct('Row',8,'Column',1));
    app.edICMin = uieditfield(lgrid,'numeric','Value',1e-3,'Limits',[1e-5 10],'Layout',struct('Row',8,'Column',2));

    uilabel(lgrid,'Text','IC Max','Layout',struct('Row',9,'Column',1));
    app.edICMax = uieditfield(lgrid,'numeric','Value',100,'Limits',[1e-3 1e4],'Layout',struct('Row',9,'Column',2));

    uilabel(lgrid,'Text','Points','Layout',struct('Row',10,'Column',1));
    app.edPts = uieditfield(lgrid,'numeric','Value',300,'Limits',[50 3000],'RoundFractionalValues','on','Layout',struct('Row',10,'Column',2));

    app.chkAnnotate = uicheckbox(lgrid,'Text','Annotate weak/moderate/strong inversion points',...
        'Value',true,'Layout',struct('Row',11,'Column',[1 2]));

    app.btnRun = uibutton(lgrid,'Text','Generate Curves','ButtonPushedFcn',@onGenerate,...
        'Layout',struct('Row',12,'Column',[1 2]));

    app.btnExport = uibutton(lgrid,'Text','Export CSV','ButtonPushedFcn',@onExport,...
        'Enable','off','Layout',struct('Row',13,'Column',[1 2]));

    uilabel(lgrid,'Text','Parsed Parameters','FontWeight','bold','Layout',struct('Row',14,'Column',[1 2]));
    app.txtParam = uitextarea(lgrid,'Editable','off','Value',{'N/A'},'Layout',struct('Row',[15 17],'Column',[1 2]));

    % ---------------- Right Panel: Plots ----------------
    right = uipanel(app.grid,'Title','Plots');
    right.Layout.Row = 1; right.Layout.Column = 2;
    rgrid = uigridlayout(right,[2 2]);
    rgrid.RowHeight = {'1x','1x'};
    rgrid.ColumnWidth = {'1x','1x'};

    app.ax1 = uiaxes(rgrid); title(app.ax1,'gm/Id vs Id/W'); grid(app.ax1,'on');
    xlabel(app.ax1,'Id/W (A/m)'); ylabel(app.ax1,'gm/Id (1/V)'); set(app.ax1,'XScale','log');
    app.ax2 = uiaxes(rgrid); title(app.ax2,'gm/Id vs Inversion Coefficient (IC)'); grid(app.ax2,'on');
    xlabel(app.ax2,'IC'); ylabel(app.ax2,'gm/Id (1/V)'); set(app.ax2,'XScale','log');
    app.ax3 = uiaxes(rgrid); title(app.ax3,'Id/W vs Vov (approx.)'); grid(app.ax3,'on');
    xlabel(app.ax3,'Vov = Vgs - Vth (V)'); ylabel(app.ax3,'Id/W (A/m)'); set(app.ax3,'YScale','log');
    app.ax4 = uiaxes(rgrid); title(app.ax4,'gm/Id target helper'); grid(app.ax4,'on');
    xlabel(app.ax4,'gm/Id (1/V)'); ylabel(app.ax4,'Id/W (A/m)'); set(app.ax4,'YScale','log');

    app.data = struct();

    % nested callbacks
    function onBrowse(~,~)
        [f,p] = uigetfile({'*.lib;*.scs;*.mdl;*.sp;*.spice;*.txt','Model files';'*.*','All files'});
        if isequal(f,0)
            return;
        end
        fullPath = fullfile(p,f);
        app.edFile.Value = fullPath;
        app.lblFileStatus.Text = ['Loaded: ', f];
        try
            params = parseModelFile(fullPath, app.ddType.Value, app.edModelName.Value);
            app.data.params = params;
            app.txtParam.Value = formatParams(params);
        catch ME
            app.txtParam.Value = {['Parse Error: ', ME.message]};
        end
    end

    function onGenerate(~,~)
        try
            file = strtrim(app.edFile.Value);
            if isempty(file) || ~isfile(file)
                uialert(app.fig,'请先选择有效模型文件。','文件错误');
                return;
            end
            if app.edICMin.Value >= app.edICMax.Value
                uialert(app.fig,'IC Min 必须小于 IC Max。','参数错误');
                return;
            end

            params = parseModelFile(file, app.ddType.Value, app.edModelName.Value);
            app.data.params = params;
            app.txtParam.Value = formatParams(params);

            cfg.Lum = app.edL.Value;
            cfg.Wum = app.edW.Value;
            cfg.TC = app.edTemp.Value;
            cfg.ICmin = app.edICMin.Value;
            cfg.ICmax = app.edICMax.Value;
            cfg.N = app.edPts.Value;

            data = computeGmidCurve(params, cfg);
            app.data.curve = data;
            drawCurves(data, app.chkAnnotate.Value);
            app.btnExport.Enable = 'on';
        catch ME
            uialert(app.fig,ME.message,'生成失败');
        end
    end

    function onExport(~,~)
        if ~isfield(app.data,'curve')
            return;
        end
        [f,p] = uiputfile('gmid_curve.csv','Export gm/Id curve');
        if isequal(f,0)
            return;
        end
        T = struct2table(app.data.curve);
        writetable(T,fullfile(p,f));
        uialert(app.fig,'CSV 已导出。','Done');
    end

    function drawCurves(d, doAnnot)
        cla(app.ax1); cla(app.ax2); cla(app.ax3); cla(app.ax4);

        plot(app.ax1, d.IdW, d.gmId, 'LineWidth',1.8);
        plot(app.ax2, d.IC, d.gmId, 'LineWidth',1.8);
        plot(app.ax3, d.Vov, d.IdW, 'LineWidth',1.8);
        plot(app.ax4, d.gmId, d.IdW, 'LineWidth',1.8);

        if doAnnot
            keyIC = [0.1 1 10];
            labels = {'Weak inv (IC=0.1)','Moderate inv (IC=1)','Strong inv (IC=10)'};
            for k=1:numel(keyIC)
                [~,idx] = min(abs(d.IC-keyIC(k)));
                hold(app.ax2,'on');
                plot(app.ax2,d.IC(idx),d.gmId(idx),'o');
                text(app.ax2,d.IC(idx),d.gmId(idx),[' ',labels{k}]);
                hold(app.ax2,'off');
            end
        end
    end
end

function params = parseModelFile(filePath, devType, modelName)
% 解析模型文件中的常见参数。若 modelName 为空则选第一个匹配器件。

    txt = fileread(filePath);
    lines = regexp(txt,'\r\n|\n','split');

    if strcmpi(devType,'NMOS')
        typeToken = 'nmos';
    else
        typeToken = 'pmos';
    end

    % 尝试抓取 .model 行
    modelIdx = [];
    chosenName = '';
    for i = 1:numel(lines)
        ln = lower(strtrim(lines{i}));
        if startsWith(ln,'.model') && contains(ln,typeToken)
            if isempty(modelName)
                modelIdx = i;
                tokens = regexp(ln,'\.model\s+(\S+)\s+','tokens','once');
                if ~isempty(tokens), chosenName = tokens{1}; end
                break;
            else
                if contains(ln, lower(modelName))
                    modelIdx = i;
                    chosenName = modelName;
                    break;
                end
            end
        end
    end

    if isempty(modelIdx)
        error('未找到匹配的 .model 行（%s）。',devType);
    end

    % 拼接该模型段（直到下一个 .model 或空白分隔）
    buf = lines{modelIdx};
    for j = modelIdx+1:numel(lines)
        l = strtrim(lines{j});
        if startsWith(lower(l),'.model')
            break;
        end
        if startsWith(l,'+') || contains(l,'=')
            buf = [buf, ' ', l]; %#ok<AGROW>
        elseif isempty(l)
            if j > modelIdx + 2
                break;
            end
        end
    end

    % 提取参数（常见别名）
    params = struct();
    params.model = chosenName;
    params.type = upper(devType);

    params.VTH0 = pickFirst(buf, {'vth0','vt0','vto'}, 0.45);
    params.U0   = pickFirst(buf, {'u0','uo'}, 450);             % cm^2/Vs (常见单位)
    params.KP   = pickFirst(buf, {'kp','beta'}, NaN);           % A/V^2
    params.TOX  = pickFirst(buf, {'tox'}, 4e-9);                % m
    params.NFACTOR = pickFirst(buf, {'nfactor','n'}, 1.4);      % EKV slope factor
    params.COX  = pickFirst(buf, {'cox'}, NaN);                 % F/m^2

    if isnan(params.COX)
        epsOx = 3.9 * 8.854e-12;
        params.COX = epsOx / params.TOX;
    end

    % 若 KP 缺失，用 U0 + Cox 估算
    if isnan(params.KP)
        mu = params.U0 * 1e-4; % cm^2/Vs -> m^2/Vs
        params.KP = mu * params.COX;
    end
end

function val = pickFirst(str, keys, defaultVal)
    val = NaN;
    for i = 1:numel(keys)
        k = keys{i};
        pat = ['(?i)\<',k,'\>\s*=\s*([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)'];
        tok = regexp(str, pat, 'tokens', 'once');
        if ~isempty(tok)
            val = str2double(tok{1});
            break;
        end
    end
    if isnan(val)
        val = defaultVal;
    end
end

function out = formatParams(p)
    out = {
        ['model = ', p.model]
        ['type = ', p.type]
        sprintf('VTH0 = %.4g V', p.VTH0)
        sprintf('U0 = %.4g cm^2/Vs', p.U0)
        sprintf('KP = %.4g A/V^2', p.KP)
        sprintf('TOX = %.4g m', p.TOX)
        sprintf('COX = %.4g F/m^2', p.COX)
        sprintf('NFACTOR = %.4g', p.NFACTOR)
        };
end

function d = computeGmidCurve(params, cfg)
% 使用 EKV 近似：
% Id = Is * [ln(1 + exp((Vgs-Vth)/(2*n*Ut)))]^2
% 令 IC = Id/Is，则 gm/Id = 1/(n*Ut) * (1-exp(-sqrt(IC)))/sqrt(IC)

    T = cfg.TC + 273.15;
    k = 1.380649e-23;
    q = 1.602176634e-19;
    Ut = k*T/q;

    n = params.NFACTOR;
    L = cfg.Lum * 1e-6;
    W = cfg.Wum * 1e-6;

    % 温度对迁移率的粗略修正（~T^-1.5）
    mu300 = params.U0 * 1e-4;
    muT = mu300 * (300/T)^1.5;

    beta = muT * params.COX * (W/L); % A/V^2
    Is = 2 * n * beta * Ut^2;

    IC = logspace(log10(cfg.ICmin), log10(cfg.ICmax), round(cfg.N)).';
    gmId = (1./(n*Ut)) .* (1 - exp(-sqrt(IC))) ./ sqrt(IC);

    Id = IC .* Is;
    IdW = Id / W;

    % 由 IC 反解近似 Vov
    % IC = [ln(1+exp(Vov/(2nUt)))]^2
    x = sqrt(IC);
    Vov = 2*n*Ut*log(exp(x)-1);

    d = struct();
    d.IC = IC;
    d.gmId = gmId;
    d.Id = Id;
    d.IdW = IdW;
    d.Vov = Vov;
    d.Is = repmat(Is,size(IC));
    d.Ut = repmat(Ut,size(IC));
end
