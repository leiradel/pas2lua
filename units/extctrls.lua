return {
  timage = {
    type = 'timage',
    fields = {
      visible = {
        type = 'boolean'
      },
      picture = {
        type = 'integer'
      },
      left = {
        type = 'left'
      },
      top = {
        type = 'left'
      },
      width = {
        type = 'left'
      },
      height = {
        type = 'left'
      },
      picture = {
        type = 'tpicture'
      },
      onmousedown = {
        type = 'procedure'
      },
      onmousemove = {
        type = 'procedure'
      },
      transparent = {
        type = 'boolean'
      },
      cursor = {
        type = 'integer'
      },
      hint = {
        type = 'string'
      },
      parentshowhint = {
        type = 'boolean'
      },
      showhint = {
        type = 'boolean'
      },
      onmouseup = {
        type = 'procedure'
      },
      autosize = {
        type = 'procedure'
      },
      stretch = {
        type = 'boolean'
      },
      center = {
        type = 'boolean'
      },
      onclick = {
        type = 'procedure'
      }
    }
  },
  ttimer = {
    type = 'ttimer',
    fields = {
      enabled = {
        type = 'boolean'
      },
      interval = {
        type = 'integer'
      },
      ontimer = {
        type = 'procedure'
      },
      top = {
        type = 'integer'
      },
      left = {
        type = 'integer'
      }
    }
  }
}
