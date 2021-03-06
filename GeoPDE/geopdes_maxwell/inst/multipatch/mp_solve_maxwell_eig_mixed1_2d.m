% MP_SOLVE_MAXWELL_EIG_MIXED1_2D: Solve the 2d Maxwell eigenvalue problem with a mixed formulation, and a B-spline discretization, in a multipatch domain.
%
% Example to solve the problem
%
%    curl (1/mu(x) curl (u)) = lambda (epsilon(x) u)   in Omega 
%          div (epsilon(x) u) = 0                      in Omega
%       (1/mu(x) curl(u)) x n = 0                      on Gamma_N
%                       u x n = 0                      on Gamma_D
%
% with the variational mixed formulation
%
%    \int (1/mu(x) curl(u) curl(v)) + \int (epsilon(x) v grad(p))
%                = lambda \int (epsilon(x) u v),   \forall v \in H_0(curl),
%                                     \int (epsilon(x) u grad(q)) = 0,
%                                                  \forall q \in H^1_0.
%
% where the domain \Omega is formed by several patches of the form F((0,1)^2).
%
% USAGE:
%
%  [geometry, msh, space, sp_mul, eigv, eigf, gnum, dofs_ornt, gnum_mul] = 
%                  mp_solve_maxwell_eig_mixed1_2d (problem_data, method_data)
%
% INPUT:
%
%  problem_data: a structure with data of the problem. It contains the fields:
%    - geo_name:     name of the file containing the geometry
%    - nmnn_sides:   sides with Neumann boundary condition (may be empty)
%    - drchlt_sides: sides with Dirichlet boundary condition
%    - c_elec_perm:  electric permittivity (epsilon in the equation)
%    - c_magn_perm:  magnetic permeability (mu in the equation)
%
%  method_data : a structure with discretization data. Its fields are:
%    - degree:     degree of the spline functions.
%    - regularity: continuity of the spline functions.
%    - nsub:       number of subelements with respect to the geometry mesh 
%                   (nsub=1 leaves the mesh unchanged)
%    - nquad:      number of points for Gaussian quadrature rule
%
% OUTPUT:
%
%  geometry:  array of geometry structures (see mp_geo_load)
%  msh:       cell array of mesh objects (see msh_2d)
%  space:     cell array of space structures (see sp_vector_2d_curl_transform)
%  sp_mul:    cell array of space structures for the multiplier (see sp_bspline_2d)
%  eigv:      the computed eigenvalues
%  eigf:      degrees of freedom of the associated eigenfunctions
%  gnum:      global numbering of the degrees of freedom, for postprocessing
%  dofs_ornt: orientation of the degrees of freedom, for postprocessing
%  gnum_mul:  global numbering of the degrees of freedom of the multiplier
%
% See also EX_MAXWELL_EIG_MIXED1_LSHAPED_MP for an example
%
% Copyright (C) 2010, 2011 Rafael Vazquez
%
%    This program is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.

%    This program is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with this program.  If not, see <http://www.gnu.org/licenses/>.

function [geometry, msh, sp, sp_mul, eigv, eigf, gnum, dofs_ornt, gnum_mul] = ...
              mp_solve_maxwell_eig_mixed1_2d (problem_data, method_data)

% Extract the fields from the data structures into local variables
data_names = fieldnames (problem_data);
for iopt  = 1:numel (data_names)
  eval ([data_names{iopt} '= problem_data.(data_names{iopt});']);
end
data_names = fieldnames (method_data);
for iopt  = 1:numel (data_names)
  eval ([data_names{iopt} '= method_data.(data_names{iopt});']);
end

% Construct geometry structure
[geometry, boundaries, interfaces] = mp_geo_load (geo_name);
npatch = numel (geometry);

msh = cell (1, npatch); 
sp = cell (1, npatch);
for iptc = 1:npatch
  [knots, zeta] = ...
         kntrefine (geometry(iptc).nurbs.knots, nsub-1, degree, regularity);
  [knots_u1, knots_u2, degree1, degree2] = knt_derham (knots, degree);

% Construct msh structure
  rule      = msh_gauss_nodes (nquad);
  [qn, qw]  = msh_set_quad_nodes (zeta, rule);
  msh{iptc} = msh_2d (zeta, qn, qw, geometry(iptc));

% Construct space structures
  sp_u1 = sp_bspline_2d (knots_u1, degree1, msh{iptc});
  sp_u2 = sp_bspline_2d (knots_u2, degree2, msh{iptc});
  sp{iptc} = sp_vector_2d_curl_transform (sp_u1, sp_u2, msh{iptc});
  clear sp_u1 sp_u2
  sp_mul{iptc} = sp_bspline_2d (knots, degree, msh{iptc});
end

[gnum, ndof, dofs_ornt] = mp_interface_hcurl_2d (interfaces, sp);
[gnum_mul, ndof_mul] = mp_interface_2d (interfaces, sp_mul);

nc_stiff = 0; nc_mass = 0; nc_saddle = 0;

for iptc = 1:npatch
% Assemble the matrices setting the orientation
  invmu = @(x, y) 1./c_magn_perm (x, y);
  [rs, cs, vs] = op_curlu_curlv_tp (sp{iptc}, sp{iptc}, msh{iptc}, invmu);
  rows_stiff(nc_stiff+(1:numel (rs))) = gnum{iptc}(rs);
  cols_stiff(nc_stiff+(1:numel (rs))) = gnum{iptc}(cs);
  vs = dofs_ornt{iptc}(rs)' .* vs .* dofs_ornt{iptc}(cs)';
  vals_stiff(nc_stiff+(1:numel (rs))) = vs;
  nc_stiff = nc_stiff + numel (rs);

  [rs, cs, vs] = op_u_v_tp (sp{iptc}, sp{iptc}, msh{iptc}, c_elec_perm);
  rows_mass(nc_mass+(1:numel (rs))) = gnum{iptc}(rs);
  cols_mass(nc_mass+(1:numel (rs))) = gnum{iptc}(cs);
  vs = dofs_ornt{iptc}(rs)' .* vs .* dofs_ornt{iptc}(cs)';
  vals_mass(nc_mass+(1:numel (rs))) = vs;
  nc_mass = nc_mass + numel (rs);

  [rs, cs, vs] = op_v_gradp_tp (sp{iptc}, sp_mul{iptc}, msh{iptc}, c_elec_perm);
  rows_saddle(nc_saddle+(1:numel (rs))) = gnum_mul{iptc}(rs);
  cols_saddle(nc_saddle+(1:numel (rs))) = gnum{iptc}(cs);
  vs = vs .* dofs_ornt{iptc}(cs)';
  vals_saddle(nc_saddle+(1:numel (rs))) = vs;
  nc_saddle = nc_saddle + numel (rs);
end

stiff_mat  = sparse (rows_stiff, cols_stiff, vals_stiff, ndof, ndof);
mass_mat   = sparse (rows_mass, cols_mass, vals_mass, ndof, ndof);
saddle_mat = sparse (rows_saddle, cols_saddle, vals_saddle, ndof_mul, ndof);

% Apply homogeneous Dirichlet boundary conditions
drchlt_dofs = [];
drchlt_dofs_mul = [];
for iref = drchlt_sides
  for bnd_side = 1:boundaries(iref).nsides
    iptc = boundaries(iref).patches(bnd_side);
    iside = boundaries(iref).faces(bnd_side);
    global_dofs = gnum{iptc}(sp{iptc}.boundary(iside).dofs);
    drchlt_dofs = [drchlt_dofs global_dofs];
    global_dofs = gnum_mul{iptc}(sp_mul{iptc}.boundary(iside).dofs);
    drchlt_dofs_mul = [drchlt_dofs_mul global_dofs];
  end
end
drchlt_dofs = unique (drchlt_dofs);
drchlt_dofs_mul = unique (drchlt_dofs_mul);
int_dofs = setdiff (1:ndof, drchlt_dofs);
int_dofs_mul = setdiff (1:ndof_mul, drchlt_dofs_mul);

% Solve the eigenvalue problem
stiff_mat  = stiff_mat (int_dofs, int_dofs);
mass_mat   = mass_mat (int_dofs, int_dofs);
saddle_mat = saddle_mat (int_dofs_mul, int_dofs);

A = [stiff_mat, saddle_mat.'; ...
     saddle_mat, sparse(numel(int_dofs_mul),numel(int_dofs_mul))];
M = [mass_mat, sparse(numel(int_dofs), numel(int_dofs_mul)); ...
     sparse(numel(int_dofs_mul), numel(int_dofs)+numel(int_dofs_mul))];

[eigf, eigv] = eig (full(A), full(M));
eigv = diag (eigv);

end

%!demo
%! ex_maxwell_eig_mixed1_Lshaped_mp
