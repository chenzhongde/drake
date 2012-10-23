classdef PlanarRigidBody < RigidBody
  
  properties
    geometry={}  % geometry (compatible w/ patch).  see parseVisual below.
    jcode=-1;        % for featherstone planar models
    jsign=1;
  end
  
  methods
    function obj = PlanarRigidBody()
      obj = obj@RigidBody();
      obj.I = zeros(3);
      obj.Xtree = eye(3);
      obj.Ttree = eye(3);
      obj.T = eye(3);
    end
    

    function body = parseVisual(body,node,model,options)
      xpts = [];
      ypts = [];
      c = .7*[1 1 1];
      
      xyz=zeros(3,1); rpy=zeros(3,1);
      origin = node.getElementsByTagName('origin').item(0);  % seems to be ok, even if origin tag doesn't exist
      if ~isempty(origin)
        if origin.hasAttribute('xyz')
          xyz = reshape(str2num(char(origin.getAttribute('xyz'))),3,1);
        end
        if origin.hasAttribute('rpy')
          rpy = reshape(str2num(char(origin.getAttribute('rpy'))),3,1);
        end
      end
        
      matnode = node.getElementsByTagName('material').item(0);
      if ~isempty(matnode)
        c = parseMaterial(model,matnode,options);
      end
      
      geomnode = node.getElementsByTagName('geometry').item(0);
      if ~isempty(geomnode)
        [xpts,ypts] = PlanarRigidBody.parseGeometry(geomnode,xyz,rpy,options);
        % % useful for testing local geometry
        % h=patch(xpts,ypts,.7*[1 1 1]);
        % axis equal
        % pause;
        % delete(h);
      
        body.geometry{1}.x = xpts;
        body.geometry{1}.y = ypts;
        body.geometry{1}.c = c;
      end        
      
      body = parseVisual@RigidBody(body,node,model,options); % also parse wrl geometry
    end
    
    function body=parseInertial(body,node,options)
      mass = 0;
      I = 1;
      xyz=zeros(3,1); rpy=zeros(3,1);
      origin = node.getElementsByTagName('origin').item(0);  % seems to be ok, even if origin tag doesn't exist
      if ~isempty(origin)
        if origin.hasAttribute('xyz')
          xyz = reshape(str2num(char(origin.getAttribute('xyz'))),3,1);
        end
        if origin.hasAttribute('rpy')
          rpy = reshape(str2num(char(origin.getAttribute('rpy'))),3,1);
        end
      end
      massnode = node.getElementsByTagName('mass').item(0);
      if ~isempty(massnode)
        if (massnode.hasAttribute('value'))
          mass = str2num(char(massnode.getAttribute('value')));
        end
      end
      inode = node.getElementsByTagName('inertia').item(0);
      if ~isempty(inode)
        switch options.view
          case 'front'
            if inode.hasAttribute('ixx'), I=str2num(char(inode.getAttribute('ixx'))); end
          case 'right'
            if inode.hasAttribute('iyy'), I=str2num(char(inode.getAttribute('iyy'))); end
          case 'top'
            if inode.hasAttribute('izz'), I=str2num(char(inode.getAttribute('izz'))); end
        end
      end      

      if any(rpy)
        error('rpy in inertia block not implemented yet (but would be easy)');
      end
      xy = [options.x_axis'; options.y_axis']*xyz;
      body.I = mcIp(mass,xy,I);
    end    
    
    function body = parseCollision(body,node,options)
      xyz=zeros(3,1); rpy=zeros(3,1);
      origin = node.getElementsByTagName('origin').item(0);  % seems to be ok, even if origin tag doesn't exist
      if ~isempty(origin)
        if origin.hasAttribute('xyz')
          xyz = reshape(str2num(char(origin.getAttribute('xyz'))),3,1);
        end
        if origin.hasAttribute('rpy')
          rpy = reshape(str2num(char(origin.getAttribute('rpy'))),3,1);
        end
      end
      
      % note: could support multiple geometry elements
      geomnode = node.getElementsByTagName('geometry').item(0);
      if ~isempty(geomnode)
        options.collision = true; 
        [xpts,ypts] = PlanarRigidBody.parseGeometry(geomnode,xyz,rpy,options);
        body.contact_pts=unique([body.contact_pts';xpts(:), ypts(:)],'rows')';
      end
    end
    
    function [x,J,dJ] = forwardKin(body,pts)
      % @retval x the position of pts (given in the body frame) in the global frame
      % @retval J the Jacobian, dxdq
      % @retval dJ the gradients of the Jacobian, dJdq
      %
      % Note: for efficiency, assumes that "doKinematics" has been called on the model
      % if pts is a 2xm matrix, then x will be a 2xm matrix
      %  and (following our gradient convention) J will be a ((2xm)x(nq))
      %  matrix, with [J1;J2;...;Jm] where Ji = dxidq 
      % and dJ will be a (2xm)x(nq^2) matrix

      m = size(pts,2);
      pts = [pts;ones(1,m)];
      x = body.T(1:2,:)*pts;
      if (nargout>1)
        nq = size(body.dTdq,1)/3;
        J = reshape(body.dTdq(1:2*nq,:)*pts,nq,[])';
        if (nargout>2)
          if isempty(body.ddTdqdq)
            error('you must call doKinematics with the second derivative option enabled'); 
          end          
          ind = repmat(1:2*nq,nq,1)+repmat((0:3*nq:3*nq*(nq-1))',1,2*nq);
          dJ = reshape(body.ddTdqdq(ind,:)*pts,nq^2,[])';
        end
      end
    end
  end
  
  methods (Static)
    
    function [x,y] = parseGeometry(node,x0,rpy,options)
      % param node DOM node for the geometry block
      % param X coordinate transform for the current body
      % option twoD true implies that I can safely ignore y.
      x=[];y=[];
      T3= [quat2rotmat(rpy2quat(rpy)),x0]; % intentially leave off the bottom row [0,0,0,1];
      T = [options.x_axis'; options.y_axis']*T3;
      wrlstr='';
      wrl_appearance_str='';
      
      childNodes = node.getChildNodes();
      for i=1:childNodes.getLength()
        thisNode = childNodes.item(i-1);
        cx=[]; cy=[]; cz=[];
        switch (lower(char(thisNode.getNodeName())))
          case 'box'
            s = str2num(char(thisNode.getAttribute('size')));
            
            cx = s(1)/2*[-1 1 1 -1 -1 1 1 -1];
            cy = s(2)/2*[1 1 1 1 -1 -1 -1 -1];
            cz = s(3)/2*[1 1 -1 -1 -1 -1 1 1];
            
            pts = T*[cx;cy;cz;ones(1,8)];
            i = convhull(pts(1,:),pts(2,:));
            x=pts(1,i)';y=pts(2,i)';
            
          case 'cylinder'
            r = str2num(char(thisNode.getAttribute('radius')));
            l = str2num(char(thisNode.getAttribute('length')));
            
            if (options.view_axis'*T3*[0;0;1;1] == 0 || ... % then it just looks like a box or
                (isfield(options,'collision') && options.collision)) % getting contacts, so use bb corners
              cx = r*[-1 1 1 -1 -1 1 1 -1];
              cy = r*[1 1 1 1 -1 -1 -1 -1];
              cz = l/2*[1 1 -1 -1 -1 -1 1 1];
              
              pts = T*[cx;cy;cz;ones(1,8)];
              i = convhull(pts(1,:),pts(2,:));
              x=pts(1,i)';y=pts(2,i)';
              
            elseif (options.view_axis'*T3*[0;0;1;1] > (1-1e-6)) % then it just looks like a circle
              theta = 0:0.1:2*pi;
              pts = r*[cos(theta); sin(theta)] + repmat(T*[0;0;0;1],1,length(theta));
              x=pts(1,:)';y=pts(2,:)';
            else  % full cylinder geometry
              error('full cylinder geometry not implemented yet');  % but wouldn't be hard
            end
            
          case 'sphere'
            r = str2num(char(thisNode.getAttribute('radius')));
            if (r==0)
                cx=0; cy=0; cz=0;
                pts = T*[0;0;0;1];
            elseif (isfield(options,'collision') && options.collision)
                pts = r*[-1 1 1 -1; 1 1 -1 -1] + repmat(T*[0;0;0;1],1,4);
            else
                theta = 0:0.1:2*pi;
                pts = r*[cos(theta); sin(theta)] + repmat(T*[0;0;0;1],1,length(theta));
            end
            x=pts(1,:)';y=pts(2,:)';


case 'mesh'
            filename=char(thisNode.getAttribute('filename'));
            [path,name,ext] = fileparts(filename);
            path = strrep(path,'package://','');
            if strcmpi(ext,'.stl')
              wrlfile = fullfile(tempdir,[name,'.wrl']);
              stl2vrml(fullfile(path,[name,ext]),tempdir);
              txt=fileread(wrlfile);
              [~,txt]=strtok(txt,'DEF');
              wrlstr=[wrlstr,sprintf('Shape {\n\tgeometry %s\n\t%s}\n',txt,wrl_appearance_str)];
            elseif strcmpi(ext,'.wrl')
              txt = fileread(filename);
              [~,txt]=strtok(txt,'DEF');
              wrlstr=[wrlstr,txt];
            end

          case {'#text','#comment'}
            % do nothing
          otherwise
            warning([char(thisNode.getNodeName()),' is not a supported element of robot/link/visual/material.']);
        end
      end


    end
  end
  
end