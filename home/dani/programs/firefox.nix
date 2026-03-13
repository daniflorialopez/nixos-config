{ ... }:

{
  programs.firefox = {
    enable = true;

    profiles = {
      personal = {
        id = 0;
        isDefault = true;
      };

      work = {
        id = 1;
      };

      lab = {
        id = 2;
      };
    };
  };
}
