function new_ripple_order = intan2ripple(new_intan_order)

if size(new_intan_order,1) > 1
    new_intan_order = new_intan_order';
end
% Find Ripple mapping for arbitrary ordering of Intan channels

% Let Intan order be 0-31
intan_order = 0:31;
% Mapping from Intan to Ripple is invariant with respect to electrode to
% Intan channel map
ripple_order = [31,29,27,25,23,21,19,17,15,13,11,9,7,5,3,1,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32];

N = numel(new_intan_order);
% Reorder Intan channels with position indices
p = zeros(1,N);
for i = 1:N
    p(i) = find(intan_order == new_intan_order(i));
end
% Check indices transform original to new
assert(isequal(intan_order(p), new_intan_order));

% Transform ripple_order with p indices
new_ripple_order = ripple_order(p);